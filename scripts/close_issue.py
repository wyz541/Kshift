#!/usr/bin/env python3
"""Validate the Kshift cleanup gate and optionally close one Issue."""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import pathlib
import re
import subprocess
import sys
from typing import Any

MARKER_RE = re.compile(
    r"<!--\s*kshift-close-gate:\s*(\{.*?\})\s*-->",
    re.DOTALL,
)
VALID_STATUSES = {"cleaned", "retained", "not-applicable"}
APPROVER = "wyz541"


class GateError(RuntimeError):
    """Raised when the close gate cannot produce a valid decision."""


def run_command(args: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    process = subprocess.run(args, check=False, capture_output=True, text=True)
    if check and process.returncode != 0:
        detail = process.stderr.strip() or process.stdout.strip() or "unknown command error"
        raise GateError(f"{' '.join(args)} failed: {detail}")
    return process


def repo_name(explicit: str | None) -> str:
    if explicit:
        if explicit.count("/") != 1 or any(not part for part in explicit.split("/")):
            raise GateError("--repo must use OWNER/REPO")
        return explicit
    process = run_command(
        ["gh", "repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"]
    )
    return process.stdout.strip()


def load_issue(repo: str, number: int) -> dict[str, Any]:
    process = run_command(
        [
            "gh",
            "issue",
            "view",
            str(number),
            "--repo",
            repo,
            "--json",
            "number,title,state,url,comments",
        ]
    )
    payload = json.loads(process.stdout)
    if payload.get("number") != number:
        raise GateError(f"GitHub returned issue {payload.get('number')} for #{number}")
    return payload


def parse_close_record(comments: list[dict[str, Any]], issue_number: int) -> dict[str, Any]:
    """Return the newest machine-readable close-gate record for one Issue."""
    for comment in reversed(comments):
        body = str(comment.get("body") or "")
        matches = list(MARKER_RE.finditer(body))
        for match in reversed(matches):
            try:
                record = json.loads(match.group(1))
            except json.JSONDecodeError:
                continue
            if not isinstance(record, dict):
                continue
            try:
                record_issue = int(record.get("issue"))
            except (TypeError, ValueError):
                continue
            if record_issue == issue_number:
                return record
    raise GateError(
        f"Issue #{issue_number} has no kshift-close-gate record. "
        "Add the approved cleanup record before closing."
    )


def _non_empty_string(record: dict[str, Any], key: str) -> bool:
    value = record.get(key)
    return isinstance(value, str) and bool(value.strip())


def _non_empty_string_list(record: dict[str, Any], key: str) -> bool:
    value = record.get(key)
    return (
        isinstance(value, list)
        and bool(value)
        and all(isinstance(item, str) and item.strip() for item in value)
    )


def _parse_date(value: str) -> dt.date | None:
    try:
        return dt.datetime.fromisoformat(value.replace("Z", "+00:00")).date()
    except (TypeError, ValueError):
        try:
            return dt.date.fromisoformat(value)
        except (TypeError, ValueError):
            return None


def validate_record(record: dict[str, Any], issue_number: int) -> list[str]:
    errors: list[str] = []
    if record.get("schemaVersion") != 1:
        errors.append("schemaVersion must be 1")
    try:
        if int(record.get("issue")) != issue_number:
            errors.append(f"issue must be {issue_number}")
    except (TypeError, ValueError):
        errors.append(f"issue must be {issue_number}")

    status = record.get("status")
    if status not in VALID_STATUSES:
        errors.append("status must be cleaned, retained, or not-applicable")

    for key in ("worktree", "branch"):
        if not _non_empty_string(record, key):
            errors.append(f"{key} must be a non-empty string")
    if not _non_empty_string_list(record, "evidenceTargets"):
        errors.append("evidenceTargets must contain at least one non-empty string")
    generated = record.get("generatedArtifacts")
    if not isinstance(generated, list) or not all(
        isinstance(item, str) and item.strip() for item in generated
    ):
        errors.append("generatedArtifacts must be a list of non-empty strings")
    checks = record.get("checks")
    if not isinstance(checks, dict) or not checks:
        errors.append("checks must be a non-empty object")
    else:
        for key in ("issueRelations", "worktreeAudit", "mainClean"):
            if key not in checks:
                errors.append(f"checks.{key} is required")
        if checks.get("mainClean") is not True:
            errors.append("checks.mainClean must be true")

    if status in {"cleaned", "retained"}:
        if str(record.get("approver", "")).strip().lstrip("@").lower() != APPROVER:
            errors.append("approved cleanup must name @wyz541 as approver")
        approved_at = record.get("approvedAt")
        if not _non_empty_string(record, "approvedAt"):
            errors.append("approvedAt is required for cleaned/retained records")
        elif _parse_date(str(approved_at)) is None:
            errors.append("approvedAt must be an ISO date or datetime")

    if status == "retained":
        if not _non_empty_string(record, "owner"):
            errors.append("owner is required for retained records")
        if not _non_empty_string(record, "reason"):
            errors.append("reason is required for retained records")
        if not _non_empty_string(record, "reviewAt"):
            errors.append("reviewAt is required for retained records")
        elif _parse_date(str(record["reviewAt"])) is None:
            errors.append("reviewAt must be an ISO date or datetime")
        elif _non_empty_string(record, "approvedAt"):
            approved = _parse_date(str(record["approvedAt"]))
            review = _parse_date(str(record["reviewAt"]))
            if approved is not None and review is not None and review > approved + dt.timedelta(days=14):
                errors.append("reviewAt must be within 14 days of approvedAt")

    if status == "not-applicable" and not _non_empty_string(record, "notApplicableReason"):
        errors.append("notApplicableReason is required for not-applicable records")

    return errors


def worktree_audit(repo_path: pathlib.Path) -> dict[str, Any]:
    process = run_command(
        [
            sys.executable,
            str(pathlib.Path(__file__).with_name("audit_worktrees.py")),
            "--repo",
            str(repo_path),
            "--format",
            "json",
        ]
    )
    try:
        return json.loads(process.stdout)
    except json.JSONDecodeError as error:
        raise GateError(f"worktree audit returned invalid JSON: {error}") from error


def relation_audit(repo: str, issue_number: int) -> str:
    process = run_command(
        [
            sys.executable,
            str(pathlib.Path(__file__).with_name("audit_issue_relations.py")),
            "--repo",
            repo,
            "--issue",
            str(issue_number),
        ]
    )
    return process.stdout


def branch_exists(repo_path: pathlib.Path, branch: str) -> bool:
    process = run_command(["git", "-C", str(repo_path), "branch", "--list", branch])
    return bool(process.stdout.strip())


def _expanded_path(value: str) -> pathlib.Path:
    return pathlib.Path(os.path.expanduser(value)).resolve()


def check_worktree_gate(
    audit: dict[str, Any],
    record: dict[str, Any],
    repo_path: pathlib.Path,
    issue_number: int,
) -> list[str]:
    errors: list[str] = []
    records = list(audit.get("worktrees") or [])
    main = next((item for item in records if item.get("role") == "main"), None)
    if main is None or main.get("disposition") != "retain":
        errors.append("main worktree must be clean and on main")
    tasks = [
        item
        for item in records
        if item.get("role") == "task" and issue_number in item.get("issueHints", [])
    ]
    status = record.get("status")
    worktree = str(record.get("worktree", ""))
    branch = str(record.get("branch", ""))

    if status == "cleaned":
        if tasks:
            errors.append(f"worktree audit still lists #{issue_number} task worktree")
        if worktree and _expanded_path(worktree).exists():
            errors.append(f"recorded worktree still exists: {worktree}")
        if branch and branch_exists(repo_path, branch):
            errors.append(f"recorded branch still exists: {branch}")
    elif status == "retained":
        if not tasks:
            errors.append(f"retained worktree for #{issue_number} is not registered")
        else:
            matching = tasks
            if not any(
                item.get("displayPath") == worktree
                or str(item.get("path", "")) == str(_expanded_path(worktree))
                for item in matching
            ):
                errors.append("retained worktree path does not match the audit")
            if any(item.get("dirty") for item in matching):
                errors.append("retained worktree must be clean")
            if branch and any(item.get("branch") != branch for item in matching):
                errors.append("retained branch does not match the audit")
        if worktree and not _expanded_path(worktree).exists():
            errors.append(f"retained worktree path does not exist: {worktree}")
        if branch and not branch_exists(repo_path, branch):
            errors.append(f"retained branch does not exist: {branch}")
    elif status == "not-applicable" and tasks:
        errors.append(f"not-applicable record still has a #{issue_number} worktree")

    return errors


def render(issue: dict[str, Any], record: dict[str, Any], relation_output: str, audit: dict[str, Any]) -> None:
    print("# Kshift close gate")
    print()
    print(f"- Issue: #{issue['number']} {issue['title']}")
    print(f"- URL: {issue['url']}")
    print(f"- Cleanup status: `{record['status']}`")
    print(f"- Worktree record: `{record['worktree']}`")
    print(f"- Branch record: `{record['branch']}`")
    print(f"- Worktree audit: `{audit['originMainCommit']}`")
    print()
    print("Relationship audit:")
    print(relation_output.rstrip())
    print()
    print("Gate checks passed.")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--issue", type=int, required=True)
    parser.add_argument("--repo", help="GitHub repository in OWNER/REPO form")
    parser.add_argument("--repo-path", type=pathlib.Path, default=pathlib.Path("."))
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--apply",
        action="store_true",
        help="Close the Issue after every check passes",
    )
    mode.add_argument(
        "--dry-run",
        action="store_true",
        help="Validate and print the close plan without changing GitHub",
    )
    args = parser.parse_args(argv)

    try:
        repo = repo_name(args.repo)
        issue = load_issue(repo, args.issue)
        if issue.get("state") != "OPEN":
            raise GateError(f"Issue #{args.issue} is already {issue.get('state')}")
        record = parse_close_record(issue.get("comments") or [], args.issue)
        errors = validate_record(record, args.issue)
        relation_output = relation_audit(repo, args.issue)
        audit = worktree_audit(args.repo_path)
        errors.extend(check_worktree_gate(audit, record, args.repo_path, args.issue))
        if errors:
            print("CLOSE GATE REJECTED", file=sys.stderr)
            for error in errors:
                print(f"- {error}", file=sys.stderr)
            return 1
        render(issue, record, relation_output, audit)
        if not args.apply:
            print("Dry run: Issue was not closed. Pass --apply to close it.")
            return 0
        run_command(
            ["gh", "issue", "close", str(args.issue), "--repo", repo, "--reason", "completed"]
        )
        print(f"Closed #{args.issue}.")
        return 0
    except (GateError, json.JSONDecodeError, KeyError, TypeError) as error:
        print(f"CLOSE GATE ERROR: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
