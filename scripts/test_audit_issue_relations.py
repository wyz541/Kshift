#!/usr/bin/env python3
"""Tests for the native relationship audit without network access."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from audit_issue_relations import audit_issue, audit_pr  # noqa: E402


def child(number: int, title: str, state: str = "OPEN") -> dict[str, object]:
    return {"number": number, "title": title, "state": state, "url": f"https://example/{number}"}


def issue(
    number: int,
    title: str,
    body: str = "",
    *,
    subissues: list[dict[str, object]] | None = None,
    blocked_by: list[int] | None = None,
) -> dict[str, object]:
    return {
        "number": number,
        "title": title,
        "state": "OPEN",
        "url": f"https://example/{number}",
        "body": body,
        "parent": None,
        "subIssues": {"nodes": subissues or []},
        "blockedBy": {"nodes": [child(item, f"[Task] {item}") for item in blocked_by or []]},
        "blocking": {"nodes": []},
        "duplicateOf": None,
    }


class IssueAuditTests(unittest.TestCase):
    def test_feature_with_delivery_and_acceptance_passes(self) -> None:
        result = audit_issue(
            issue(
                10,
                "[Feature] 工程治理：完成规则",
                subissues=[
                    child(11, "[Task] 交付规则"),
                    child(12, "[Acceptance] 验收规则"),
                ],
            )
        )
        self.assertFalse(result.errors)

    def test_feature_without_acceptance_fails(self) -> None:
        result = audit_issue(
            issue(10, "[Feature] 工程治理：完成规则", subissues=[child(11, "[Task] 交付规则")])
        )
        self.assertIn("FEATURE-ACCEPTANCE", {item.code for item in result.errors})

    def test_feature_body_with_child_list_fails(self) -> None:
        result = audit_issue(
            issue(
                10,
                "[Feature] 工程治理：完成规则",
                "子 Issue：#11、#12",
                subissues=[
                    child(11, "[Task] 交付规则"),
                    child(12, "[Acceptance] 验收规则"),
                ],
            )
        )
        self.assertIn("FEATURE-CHILD-LIST", {item.code for item in result.errors})

    def test_acceptance_requires_all_delivery_blockers(self) -> None:
        acceptance = issue(12, "[Acceptance] 验收规则", blocked_by=[11])
        acceptance["parent"] = {
            "number": 10,
            "title": "[Feature] 工程治理：完成规则",
            "state": "OPEN",
            "url": "https://example/10",
            "subIssues": {
                "nodes": [
                    child(11, "[Task] 交付规则"),
                    child(12, "[Acceptance] 验收规则"),
                    child(13, "[Task] 第二个交付规则"),
                ]
            },
        }
        result = audit_issue(acceptance)
        self.assertIn("ACCEPTANCE-BLOCKERS", {item.code for item in result.errors})

    def test_research_requires_one_source_discussion(self) -> None:
        result = audit_issue(
            issue(
                20,
                "[Research] 确认规则",
                "## 来源 Discussion\n\nhttps://github.com/example/repo/discussions/1",
            )
        )
        self.assertFalse(result.errors)

    def test_research_rejects_multiple_discussions(self) -> None:
        result = audit_issue(
            issue(
                20,
                "[Research] 确认规则",
                "## 来源 Discussion\n\n"
                "https://github.com/example/repo/discussions/1\n"
                "https://github.com/example/repo/discussions/2",
            )
        )
        self.assertIn("RESEARCH-SOURCE-MULTIPLE", {item.code for item in result.errors})

    def test_direct_research_can_write_none(self) -> None:
        result = audit_issue(issue(20, "[Research] 确认规则", "## 来源 Discussion\n\n无"))
        self.assertFalse(result.errors)


class PullRequestAuditTests(unittest.TestCase):
    def pull_request(self, body: str, closing: list[int] | None = None) -> dict[str, object]:
        closing_nodes = [
            {
                "number": number,
                "title": f"Issue {number}",
                "state": "OPEN",
                "url": f"https://example/{number}",
                "repository": {"nameWithOwner": "example/repo"},
            }
            for number in closing or []
        ]
        return {
            "number": 30,
            "title": "docs(governance): define issue relations",
            "state": "OPEN",
            "url": "https://example/pr/30",
            "body": body,
            "closingIssuesReferences": {"nodes": closing_nodes},
        }

    def test_part_of_passes_without_closing_reference(self) -> None:
        result = audit_pr(self.pull_request("Part of #26"))
        self.assertFalse(result.errors)

    def test_closes_requires_closing_reference(self) -> None:
        result = audit_pr(self.pull_request("Closes #26"))
        self.assertIn("PR-CLOSING-REFERENCE", {item.code for item in result.errors})

    def test_missing_tracking_fails(self) -> None:
        result = audit_pr(self.pull_request("Issue: #26"))
        self.assertIn("PR-TRACKING", {item.code for item in result.errors})


if __name__ == "__main__":
    unittest.main()
