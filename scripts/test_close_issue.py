#!/usr/bin/env python3
"""Unit tests for the local close gate."""
from __future__ import annotations

import json
import pathlib
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from audit_closed_issues import audit_issue as audit_closed_issue  # noqa: E402
from close_issue import (  # noqa: E402
    check_worktree_gate,
    parse_close_record,
    validate_record,
)


def base_record(status: str = "cleaned") -> dict[str, object]:
    return {
        "schemaVersion": 1,
        "issue": 65,
        "status": status,
        "worktree": "~/repo/_worktrees/Kshift/missing-issue-65",
        "branch": "issue/65-close-gate",
        "generatedArtifacts": ["target/"],
        "evidenceTargets": ["PR #200", "Issue #65"],
        "checks": {"worktreeAudit": "cleanup-candidate", "issueRelations": "PASS", "mainClean": True},
        "approver": "@wyz541",
        "approvedAt": "2026-11-24T16:50:40+08:00",
    }


def marker(record: dict[str, object]) -> str:
    return f"<!-- kshift-close-gate: {json.dumps(record, sort_keys=True)} -->"


def clean_audit(*tasks: dict[str, object]) -> dict[str, object]:
    return {
        "originMainCommit": "abc123",
        "worktrees": [
            {"role": "main", "disposition": "retain"},
            *tasks,
        ],
    }


class CloseGateTests(unittest.TestCase):
    def test_parse_latest_matching_record(self) -> None:
        old = base_record()
        old["status"] = "pending"
        new = base_record("cleaned")
        comments = [
            {"body": "noise"},
            {"body": marker(old)},
            {"body": "more noise\n" + marker(new)},
        ]
        self.assertEqual(parse_close_record(comments, 65)["status"], "cleaned")

    def test_cleaned_record_passes(self) -> None:
        self.assertEqual(validate_record(base_record(), 65), [])

    def test_cleaned_record_requires_approval(self) -> None:
        record = base_record()
        record.pop("approver")
        self.assertTrue(validate_record(record, 65))

    def test_retained_record_requires_review_within_fourteen_days(self) -> None:
        record = base_record("retained")
        record.update(
            {
                "owner": "@wyz541",
                "reason": "reproduction",
                "reviewAt": "2026-12-10",
            }
        )
        self.assertIn(
            "reviewAt must be within 14 days of approvedAt",
            validate_record(record, 65),
        )

    def test_not_applicable_requires_reason(self) -> None:
        record = base_record("not-applicable")
        record.pop("approver", None)
        record.pop("approvedAt", None)
        self.assertIn(
            "notApplicableReason is required for not-applicable records",
            validate_record(record, 65),
        )
        record["notApplicableReason"] = "documentation-only change"
        self.assertEqual(validate_record(record, 65), [])

    def test_cleaned_worktree_must_be_absent(self) -> None:
        with patch("close_issue.branch_exists", return_value=False):
            self.assertEqual(
                check_worktree_gate(
                    clean_audit(),
                    base_record(),
                    pathlib.Path("/tmp"),
                    65,
                ),
                [],
            )

    def test_cleaned_worktree_still_registered_is_rejected(self) -> None:
        task = {
            "role": "task",
            "issueHints": [65],
            "displayPath": "~/repo/_worktrees/Kshift/issue-65-close-gate",
            "path": "/tmp/issue-65-close-gate",
            "branch": "issue/65-close-gate",
            "dirty": False,
        }
        with patch("close_issue.branch_exists", return_value=True):
            errors = check_worktree_gate(
                clean_audit(task),
                base_record(),
                pathlib.Path("/tmp"),
                65,
            )
        self.assertTrue(any("still lists" in error for error in errors))

    def test_retained_worktree_must_match_audit(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            worktree = pathlib.Path(temporary)
            record = base_record("retained")
            record.update(
                {
                    "worktree": str(worktree),
                    "owner": "@wyz541",
                    "reason": "reproduction",
                    "reviewAt": "2026-12-08",
                }
            )
            task = {
                "role": "task",
                "issueHints": [65],
                "displayPath": str(worktree),
                "path": str(worktree),
                "branch": "issue/65-close-gate",
                "dirty": False,
            }
            with patch("close_issue.branch_exists", return_value=True):
                self.assertEqual(
                    check_worktree_gate(
                        clean_audit(task),
                        record,
                        pathlib.Path("/tmp"),
                        65,
                    ),
                    [],
                )

    def test_not_applicable_cannot_hide_a_registered_worktree(self) -> None:
        record = base_record("not-applicable")
        record.pop("approver", None)
        record.pop("approvedAt", None)
        record["notApplicableReason"] = "no local changes"
        task = {
            "role": "task",
            "issueHints": [65],
            "displayPath": "~/repo/_worktrees/Kshift/issue-65-close-gate",
            "path": "/tmp/issue-65-close-gate",
            "branch": "issue/65-close-gate",
            "dirty": False,
        }
        errors = check_worktree_gate(clean_audit(task), record, pathlib.Path("/tmp"), 65)
        self.assertTrue(any("not-applicable" in error for error in errors))


class ClosedIssueAuditTests(unittest.TestCase):
    def closed_issue(self, record: dict[str, object] | None) -> dict[str, object]:
        comments = [] if record is None else [{"body": marker(record)}]
        return {
            "number": 65,
            "title": "Close gate",
            "state": "CLOSED",
            "comments": comments,
        }

    def test_closed_issue_with_valid_record_passes(self) -> None:
        self.assertEqual(audit_closed_issue(self.closed_issue(base_record())), [])

    def test_closed_issue_without_record_is_reported(self) -> None:
        self.assertTrue(audit_closed_issue(self.closed_issue(None)))


if __name__ == "__main__":
    unittest.main()
