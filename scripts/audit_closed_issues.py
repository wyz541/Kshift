#!/usr/bin/env python3
"""Report closed Issues that lack a valid kshift-close-gate record."""
from __future__ import annotations

import argparse
import json
import pathlib
import sys
from typing import Any

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from close_issue import GateError, parse_close_record, run_command, validate_record  # noqa: E402


def load_closed_issues(repo: str, limit: int, numbers: list[int]) -> list[dict[str, Any]]:
    if numbers:
        issues = []
        for number in numbers:
            process = run_command(
                [
                    "gh",
                    "issue",
                    "view",
                    str(number),
                    "--repo",
                    repo,
                    "--json",
                    "number,title,state,url,closedAt,comments",
                ]
            )
            issues.append(json.loads(process.stdout))
        return issues
    process = run_command(
        [
            "gh",
            "issue",
            "list",
            "--repo",
            repo,
            "--state",
            "closed",
            "--limit",
            str(limit),
            "--json",
            "number,title,state,url,closedAt,comments",
        ]
    )
    return json.loads(process.stdout)


def audit_issue(issue: dict[str, Any]) -> list[str]:
    if issue.get("state") != "CLOSED":
        return [f"issue is {issue.get('state')}, not CLOSED"]
    try:
        record = parse_close_record(issue.get("comments") or [], int(issue["number"]))
    except GateError as error:
        return [str(error)]
    return validate_record(record, int(issue["number"]))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--limit", type=int, default=100)
    parser.add_argument("--issue", type=int, action="append", default=[])
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args(argv)

    try:
        issues = load_closed_issues(args.repo, args.limit, args.issue)
        missing = 0
        for issue in issues:
            number = int(issue["number"])
            errors = audit_issue(issue)
            if errors:
                missing += 1
                print(f"MISSING #{number} {issue.get('title', '')}")
                for error in errors:
                    print(f"  - {error}")
            else:
                print(f"PASS #{number} {issue.get('title', '')}")
        print(f"SUMMARY: {len(issues) - missing} pass, {missing} missing/invalid")
        return 1 if args.strict and missing else 0
    except (GateError, json.JSONDecodeError, KeyError, TypeError) as error:
        print(f"AUDIT ERROR: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
