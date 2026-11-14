#!/usr/bin/env python3
"""Audit Git worktrees without changing refs, indexes, or working files."""
from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import subprocess
import sys
from dataclasses import dataclass, field
from typing import Any


ALLOWED_GIT_COMMANDS = {
    "for-each-ref",
    "merge-base",
    "rev-list",
    "rev-parse",
    "status",
    "worktree",
}
ISSUE_HINT_RE = re.compile(
    r"(?:^|[^A-Za-z0-9])(?:issue|task|research|docs)[-_/](\d+)(?:[^0-9]|$)",
    re.IGNORECASE,
)


class AuditError(RuntimeError):
    """Raised when a read-only audit command cannot produce valid evidence."""


@dataclass
class WorktreeSnapshot:
    path: str
    head: str
    branch_ref: str | None
    detached: bool = False
    locked: str | None = None
    prunable: str | None = None


@dataclass
class AuditRecord:
    path: str
    display_path: str
    head: str
    branch_ref: str | None
    branch: str | None
    detached: bool
    role: str
    is_current: bool
    issue_hints: list[int]
    dirty: bool = False
    status_entries: list[str] = field(default_factory=list)
    merged_to_origin_main: bool = False
    commits_ahead: int | None = None
    commits_behind: int | None = None
    remote_branch: str | None = None
    remote_branch_exists: bool = False
    unpushed_commits: int | None = None
    locked: bool = False
    prunable: bool = False
    disposition: str = "manual-review"
    reasons: list[str] = field(default_factory=list)

    def as_dict(self) -> dict[str, Any]:
        return {
            "path": self.path,
            "displayPath": self.display_path,
            "head": self.head,
            "branchRef": self.branch_ref,
            "branch": self.branch,
            "detached": self.detached,
            "role": self.role,
            "isCurrent": self.is_current,
            "issueHints": self.issue_hints,
            "dirty": self.dirty,
            "statusEntries": self.status_entries,
            "mergedToOriginMain": self.merged_to_origin_main,
            "commitsAheadOfOriginMain": self.commits_ahead,
            "commitsBehindOriginMain": self.commits_behind,
            "remoteBranch": self.remote_branch,
            "remoteBranchExists": self.remote_branch_exists,
            "unpushedCommits": self.unpushed_commits,
            "locked": self.locked,
            "prunable": self.prunable,
            "disposition": self.disposition,
            "reasons": self.reasons,
        }


def display_path(path: str) -> str:
    home = str(pathlib.Path.home())
    if path == home:
        return "~"
    if path.startswith(home + os.sep):
        return "~" + path[len(home) :]
    return path


def run_git(repo: pathlib.Path, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    """Run one explicitly allowed read-only Git command."""
    if not args or args[0] not in ALLOWED_GIT_COMMANDS:
        command = " ".join(args) if args else "<missing>"
        raise AuditError(f"Blocked non-audit Git command: git {command}")
    if args[0] == "worktree" and (len(args) < 2 or args[1] != "list"):
        raise AuditError("Only 'git worktree list' is allowed")

    environment = os.environ.copy()
    environment["GIT_OPTIONAL_LOCKS"] = "0"
    environment["GIT_TERMINAL_PROMPT"] = "0"
    environment["GIT_PAGER"] = "cat"
    process = subprocess.run(
        ["git", "-C", str(repo), *args],
        check=False,
        capture_output=True,
        text=True,
        env=environment,
    )
    if check and process.returncode != 0:
        detail = process.stderr.strip() or process.stdout.strip() or "unknown Git error"
        raise AuditError(f"git {' '.join(args)} failed: {detail}")
    return process


def resolve_repo(repo: pathlib.Path) -> tuple[pathlib.Path, str]:
    if not repo.exists():
        raise AuditError(f"Repository path does not exist: {repo}")
    process = run_git(repo, "rev-parse", "--show-toplevel")
    return pathlib.Path(process.stdout.strip()).resolve(), process.stdout.strip()


def parse_worktrees(repo: pathlib.Path) -> list[WorktreeSnapshot]:
    output = run_git(repo, "worktree", "list", "--porcelain").stdout
    records: list[WorktreeSnapshot] = []
    current: dict[str, Any] = {}
    for line in output.splitlines() + [""]:
        if not line:
            if current:
                if "worktree" not in current or "HEAD" not in current:
                    raise AuditError("Malformed 'git worktree list --porcelain' output")
                records.append(
                    WorktreeSnapshot(
                        path=current["worktree"],
                        head=current["HEAD"],
                        branch_ref=current.get("branch"),
                        detached="detached" in current,
                        locked=current.get("locked"),
                        prunable=current.get("prunable"),
                    )
                )
                current = {}
            continue
        key, separator, value = line.partition(" ")
        current[key] = value if separator else ""
    return records


def issue_hints(*values: str | None) -> list[int]:
    found: set[int] = set()
    for value in values:
        if not value:
            continue
        found.update(int(match) for match in ISSUE_HINT_RE.findall(value))
    return sorted(found)


def merge_state(repo: pathlib.Path, head: str, origin_main: str) -> tuple[bool, int, int]:
    ancestor = run_git(repo, "merge-base", "--is-ancestor", head, origin_main, check=False)
    if ancestor.returncode not in (0, 1):
        detail = ancestor.stderr.strip() or ancestor.stdout.strip() or "unknown Git error"
        raise AuditError(f"Unable to compare {head} with {origin_main}: {detail}")
    counts = run_git(repo, "rev-list", "--left-right", "--count", f"{origin_main}...{head}")
    values = counts.stdout.strip().split()
    if len(values) != 2 or not all(value.isdigit() for value in values):
        raise AuditError(f"Unexpected rev-list output: {counts.stdout.strip()}")
    behind, ahead = (int(value) for value in values)
    return ancestor.returncode == 0, ahead, behind


def inspect_worktree(
    snapshot: WorktreeSnapshot,
    *,
    main_worktree: str,
    current_worktree: str,
    origin_main: str,
    remote: str,
) -> AuditRecord:
    path = pathlib.Path(snapshot.path)
    branch = None
    if snapshot.branch_ref and snapshot.branch_ref.startswith("refs/heads/"):
        branch = snapshot.branch_ref[len("refs/heads/") :]
    record = AuditRecord(
        path=snapshot.path,
        display_path=display_path(snapshot.path),
        head=snapshot.head,
        branch_ref=snapshot.branch_ref,
        branch=branch,
        detached=snapshot.detached,
        role="main" if snapshot.path == main_worktree else "task",
        is_current=pathlib.Path(snapshot.path).resolve() == pathlib.Path(current_worktree).resolve(),
        issue_hints=issue_hints(path.name, branch),
        locked=snapshot.locked is not None,
        prunable=snapshot.prunable is not None,
    )

    if not path.is_dir():
        record.reasons.append("path-missing")
        return record

    status = run_git(path, "status", "--porcelain=v1", "--untracked-files=normal")
    record.status_entries = [line for line in status.stdout.splitlines() if line]
    record.dirty = bool(record.status_entries)
    record.merged_to_origin_main, record.commits_ahead, record.commits_behind = merge_state(
        path, snapshot.head, origin_main
    )

    if branch:
        record.remote_branch = f"refs/remotes/{remote}/{branch}"
        remote_ref = run_git(path, "rev-parse", "--verify", "--quiet", record.remote_branch, check=False)
        record.remote_branch_exists = remote_ref.returncode == 0

        if record.remote_branch_exists:
            count = run_git(path, "rev-list", "--count", f"{record.remote_branch}..{snapshot.head}")
            record.unpushed_commits = int(count.stdout.strip())
        else:
            record.unpushed_commits = record.commits_ahead

    if record.role == "main":
        main_branch = run_git(path, "rev-parse", "--abbrev-ref", "HEAD").stdout.strip()
        if main_branch != "main":
            record.reasons.append("main-worktree-not-on-main")
        if record.dirty:
            record.reasons.append("main-worktree-dirty")
        record.disposition = "retain" if not record.reasons else "manual-review"
    elif record.is_current:
        record.disposition = "active"
        record.reasons.append("current-worktree")
    else:
        if record.locked:
            record.reasons.append("worktree-locked")
        if record.prunable:
            record.reasons.append("worktree-prunable")
        if record.dirty:
            record.reasons.append("uncommitted-changes")
        if not record.merged_to_origin_main:
            record.reasons.append("unmerged-to-origin-main")
        record.disposition = "cleanup-candidate" if not record.reasons else "manual-review"

    return record


def build_audit(repo: pathlib.Path, remote: str, expected_count: int | None) -> dict[str, Any]:
    resolved_repo, _ = resolve_repo(repo)
    snapshots = parse_worktrees(resolved_repo)
    if not snapshots:
        raise AuditError("No Git worktrees found")

    origin_ref = f"refs/remotes/{remote}/main"
    origin_process = run_git(resolved_repo, "rev-parse", "--verify", origin_ref, check=False)
    if origin_process.returncode != 0:
        raise AuditError(f"Required audit reference {remote}/main is missing; run a manual fetch first")
    origin_main = origin_process.stdout.strip()
    current_worktree = run_git(resolved_repo, "rev-parse", "--show-toplevel").stdout.strip()
    main_worktree = snapshots[0].path

    records = [
        inspect_worktree(
            snapshot,
            main_worktree=main_worktree,
            current_worktree=current_worktree,
            origin_main=origin_main,
            remote=remote,
        )
        for snapshot in snapshots
    ]
    records.sort(key=lambda record: (record.role != "main", record.path))

    task_records = [record for record in records if record.role == "task"]
    summary = {
        "registeredWorktrees": len(records),
        "taskWorktrees": len(task_records),
        "expectedTaskWorktrees": expected_count,
        "taskWorktreeCountMatches": expected_count is None or len(task_records) == expected_count,
        "cleanupCandidates": sum(record.disposition == "cleanup-candidate" for record in task_records),
        "manualReview": sum(record.disposition == "manual-review" for record in task_records),
        "active": sum(record.disposition == "active" for record in task_records),
        "dirty": sum(record.dirty for record in task_records),
        "unmerged": sum(not record.merged_to_origin_main for record in task_records),
    }
    return {
        "schemaVersion": 1,
        "readOnly": True,
        "auditRoot": str(resolved_repo),
        "mainWorktree": main_worktree,
        "remote": remote,
        "originMainCommit": origin_main,
        "summary": summary,
        "worktrees": [record.as_dict() for record in records],
    }


def print_markdown(audit: dict[str, Any]) -> None:
    summary = audit["summary"]
    expected = summary["expectedTaskWorktrees"]
    print("# Worktree audit")
    print()
    print("Read-only snapshot. The command does not fetch, prune, remove, rename, or delete.")
    print()
    print(f"- Audit root: `{display_path(audit['auditRoot'])}`")
    print(f"- Main worktree: `{display_path(audit['mainWorktree'])}`")
    print(f"- Base: `{audit['remote']}/main` at `{audit['originMainCommit']}`")
    print(
        "- Counts: "
        f"{summary['taskWorktrees']} task worktrees, "
        f"{summary['cleanupCandidates']} cleanup candidates, "
        f"{summary['manualReview']} manual review, "
        f"{summary['active']} active"
    )
    if expected is not None:
        status = "match" if summary["taskWorktreeCountMatches"] else "mismatch"
        print(f"- Expected task worktrees: `{expected}` ({status})")
    print()
    print("| Role | Disposition | Issues | Branch | HEAD | Dirty | Merged | Remote | Unpushed | Path |")
    print("| --- | --- | --- | --- | --- | --- | --- | --- | ---: | --- |")
    for record in audit["worktrees"]:
        issues = ", ".join(f"#{number}" for number in record["issueHints"]) or "unknown"
        branch = record["branch"] or "detached"
        head = record["head"][:12]
        dirty = "yes" if record["dirty"] else "no"
        merged = "yes" if record["mergedToOriginMain"] else "no"
        remote = "present" if record["remoteBranchExists"] else "missing"
        unpushed = "-" if record["unpushedCommits"] is None else str(record["unpushedCommits"])
        print(
            f"| {record['role']} | {record['disposition']} | {issues} | `{branch}` | "
            f"`{head}` | {dirty} | {merged} | {remote} | {unpushed} | "
            f"`{record['displayPath']}` |"
        )
    manual = [record for record in audit["worktrees"] if record["disposition"] == "manual-review"]
    if manual:
        print()
        print("## Manual review reasons")
        print()
        for record in manual:
            reasons = ", ".join(record["reasons"]) or "none"
            print(f"- `{record['displayPath']}`: {reasons}")


def strict_failures(audit: dict[str, Any]) -> list[str]:
    summary = audit["summary"]
    failures: list[str] = []
    if not summary["taskWorktreeCountMatches"]:
        failures.append(
            f"expected {summary['expectedTaskWorktrees']} task worktrees, found {summary['taskWorktrees']}"
        )
    main = next(record for record in audit["worktrees"] if record["role"] == "main")
    if main["disposition"] != "retain":
        failures.append("main worktree is not a clean main checkout")
    if any(record["reasons"] == ["path-missing"] for record in audit["worktrees"]):
        failures.append("at least one registered worktree path is missing")
    return failures


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=".", help="Path inside the target Git repository")
    parser.add_argument("--remote", default="origin", help="Remote used for push and merge checks")
    parser.add_argument(
        "--expected-task-worktrees",
        type=int,
        help="Expected count of registered task worktrees",
    )
    parser.add_argument("--format", choices=("markdown", "json"), default="markdown")
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Fail on count mismatch, invalid main checkout, or missing registered paths",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    try:
        audit = build_audit(pathlib.Path(args.repo), args.remote, args.expected_task_worktrees)
    except AuditError as error:
        print(f"AUDIT ERROR: {error}", file=sys.stderr)
        return 2

    if args.format == "json":
        print(json.dumps(audit, indent=2, sort_keys=True))
    else:
        print_markdown(audit)

    failures = strict_failures(audit) if args.strict else []
    for failure in failures:
        print(f"STRICT: {failure}", file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
