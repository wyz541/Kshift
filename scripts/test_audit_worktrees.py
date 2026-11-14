#!/usr/bin/env python3
"""Tests for the read-only worktree audit."""
from __future__ import annotations

import hashlib
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest


SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from audit_worktrees import AuditError, run_git  # noqa: E402


def git(repo: pathlib.Path, *args: str) -> str:
    environment = os.environ.copy()
    environment["GIT_OPTIONAL_LOCKS"] = "0"
    process = subprocess.run(
        ["git", "-C", str(repo), *args],
        check=True,
        capture_output=True,
        text=True,
        env=environment,
    )
    return process.stdout.strip()


def write(path: pathlib.Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def file_digest(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


class WorktreeAuditTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temporary.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        git(self.repo, "init", "-b", "main")
        git(self.repo, "config", "user.name", "Audit Test")
        git(self.repo, "config", "user.email", "audit@example.invalid")
        write(self.repo / "README.md", "initial\n")
        git(self.repo, "add", "README.md")
        git(self.repo, "commit", "-m", "Initial")
        git(self.repo, "update-ref", "refs/remotes/origin/main", "HEAD")

        self.clean = self.root / "issue-48-clean"
        self.dirty = self.root / "issue-49-dirty"
        self.unmerged = self.root / "issue-50-unmerged"
        git(self.repo, "worktree", "add", "-b", "issue/48-clean", str(self.clean), "HEAD")
        git(self.repo, "worktree", "add", "-b", "issue/49-dirty", str(self.dirty), "HEAD")
        git(self.repo, "worktree", "add", "-b", "issue/50-unmerged", str(self.unmerged), "HEAD")
        git(self.repo, "update-ref", "refs/remotes/origin/issue/48-clean", "HEAD")

        write(self.dirty / "local-evidence.txt", "not committed\n")
        write(self.unmerged / "feature.txt", "unmerged\n")
        git(self.unmerged, "add", "feature.txt")
        git(self.unmerged, "commit", "-m", "Add unmerged work")

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def run_audit(self, *extra: str) -> subprocess.CompletedProcess[str]:
        environment = os.environ.copy()
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        return subprocess.run(
            [
                sys.executable,
                str(SCRIPT_DIR / "audit_worktrees.py"),
                "--repo",
                str(self.repo),
                "--format",
                "json",
                *extra,
            ],
            check=False,
            capture_output=True,
            text=True,
            env=environment,
        )

    def snapshot(self) -> dict[str, object]:
        worktrees = [self.repo, self.clean, self.dirty, self.unmerged]
        statuses = {str(path): git(path, "status", "--porcelain=v1", "--untracked-files=normal") for path in worktrees}
        refs = git(self.repo, "for-each-ref", "--format=%(refname)%00%(objectname)")
        worktree_list = git(self.repo, "worktree", "list", "--porcelain")
        files: dict[str, str] = {}
        for path in sorted(self.root.rglob("*")):
            if path.is_file():
                files[str(path.relative_to(self.root))] = file_digest(path)
        return {
            "statuses": statuses,
            "refs": refs,
            "worktreeList": worktree_list,
            "files": files,
        }

    def test_classifies_cleanup_candidate_and_manual_review(self) -> None:
        process = self.run_audit("--expected-task-worktrees", "3")
        self.assertEqual(process.returncode, 0, process.stderr)
        audit = json.loads(process.stdout)
        records = {record["issueHints"][0]: record for record in audit["worktrees"] if record["role"] == "task"}

        self.assertEqual(records[48]["disposition"], "cleanup-candidate")
        self.assertTrue(records[48]["mergedToOriginMain"])
        self.assertTrue(records[48]["remoteBranchExists"])

        self.assertEqual(records[49]["disposition"], "manual-review")
        self.assertTrue(records[49]["dirty"])
        self.assertIn("uncommitted-changes", records[49]["reasons"])

        self.assertEqual(records[50]["disposition"], "manual-review")
        self.assertFalse(records[50]["mergedToOriginMain"])
        self.assertIn("unmerged-to-origin-main", records[50]["reasons"])
        self.assertEqual(records[50]["unpushedCommits"], 1)

        self.assertEqual(audit["summary"]["taskWorktrees"], 3)
        self.assertEqual(audit["summary"]["cleanupCandidates"], 1)
        self.assertEqual(audit["summary"]["manualReview"], 2)
        self.assertTrue(audit["readOnly"])

    def test_expected_count_mismatch_only_fails_strict_mode(self) -> None:
        normal = self.run_audit("--expected-task-worktrees", "19")
        self.assertEqual(normal.returncode, 0, normal.stderr)
        self.assertFalse(json.loads(normal.stdout)["summary"]["taskWorktreeCountMatches"])

        strict = self.run_audit("--expected-task-worktrees", "19", "--strict")
        self.assertEqual(strict.returncode, 1)
        self.assertIn("expected 19 task worktrees, found 3", strict.stderr)

    def test_audit_does_not_change_git_state_or_files(self) -> None:
        before = self.snapshot()
        process = self.run_audit("--expected-task-worktrees", "3")
        self.assertEqual(process.returncode, 0, process.stderr)
        after = self.snapshot()
        self.assertEqual(before, after)

    def test_run_git_rejects_destructive_commands(self) -> None:
        for args in (
            ("worktree", "remove", str(self.clean)),
            ("branch", "-D", "issue/48-clean"),
            ("reset", "--hard"),
        ):
            with self.subTest(args=args), self.assertRaises(AuditError):
                run_git(self.repo, *args)


if __name__ == "__main__":
    unittest.main()
