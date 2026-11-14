#!/usr/bin/env python3
"""Audit native GitHub issue and pull request relationships."""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass, field
from typing import Any, Iterable


ISSUE_QUERY = """
query IssueRelations($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    issue(number: $number) {
      number
      title
      state
      url
      body
      parent {
        number
        title
        state
        url
        subIssues(first: 100) {
          totalCount
          nodes { number title state url }
        }
      }
      subIssues(first: 100) {
        totalCount
        nodes { number title state url }
      }
      blockedBy(first: 100) {
        totalCount
        nodes { number title state url }
      }
      blocking(first: 100) {
        totalCount
        nodes { number title state url }
      }
      duplicateOf { number title state url }
    }
  }
}
""".strip()


PR_QUERY = """
query PullRequestRelations($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      number
      title
      state
      url
      body
      closingIssuesReferences(first: 100) {
        totalCount
        nodes {
          number
          title
          state
          url
          repository { nameWithOwner }
        }
      }
    }
  }
}
""".strip()


TYPE_RE = re.compile(r"^\[(Feature|Acceptance|Task|Bug|Research|Docs|Release|Security)\]")
ISSUE_REF_RE = re.compile(r"(?<![A-Za-z0-9_])#(\d+)\b")
ISSUE_URL_RE = re.compile(r"https://github\.com/[^/\s]+/[^/\s]+/issues/(\d+)\b")
DISCUSSION_RE = re.compile(r"https://github\.com/[^/\s]+/[^/\s]+/discussions/(\d+)\b")
TRACKING_RE = re.compile(
    r"\b(Closes|Part\s+of)\s+"
    r"(?:https://github\.com/[^/\s]+/[^/\s]+/issues/\d+|"
    r"(?:[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)?#\d+)\b",
    re.IGNORECASE,
)
HEADING_RE = re.compile(r"^(#{1,6})\s+(.+?)\s*$")


@dataclass
class Finding:
    severity: str
    code: str
    message: str


@dataclass
class AuditResult:
    subject: str
    title: str
    url: str
    findings: list[Finding] = field(default_factory=list)
    facts: list[str] = field(default_factory=list)

    @property
    def errors(self) -> list[Finding]:
        return [item for item in self.findings if item.severity == "error"]

    @property
    def warnings(self) -> list[Finding]:
        return [item for item in self.findings if item.severity == "warning"]


def issue_type(title: str) -> str | None:
    match = TYPE_RE.match(title)
    return match.group(1) if match else None


def section(text: str, wanted: str) -> str:
    """Return one Markdown section without its heading."""
    lines = text.splitlines()
    start: int | None = None
    level = 0
    for index, line in enumerate(lines):
        match = HEADING_RE.match(line)
        if not match:
            continue
        if start is not None and len(match.group(1)) <= level:
            return "\n".join(lines[start:index]).strip()
        if start is None and match.group(2).strip().casefold() == wanted.casefold():
            start = index + 1
            level = len(match.group(1))
    if start is None:
        return ""
    return "\n".join(lines[start:]).strip()


def referenced_issue_numbers(body: str) -> set[int]:
    numbers = {int(value) for value in ISSUE_REF_RE.findall(body)}
    numbers.update(int(value) for value in ISSUE_URL_RE.findall(body))
    return numbers


def nodes(connection: dict[str, Any] | None) -> list[dict[str, Any]]:
    if not connection:
        return []
    return list(connection.get("nodes") or [])


def issue_numbers(connection: dict[str, Any] | None) -> list[int]:
    return sorted(int(node["number"]) for node in nodes(connection))


def audit_issue(issue: dict[str, Any]) -> AuditResult:
    result = AuditResult(
        subject=f"#{issue['number']}",
        title=str(issue.get("title", "")),
        url=str(issue.get("url", "")),
    )
    body = str(issue.get("body") or "")
    kind = issue_type(result.title)
    subissues = nodes(issue.get("subIssues"))
    blocked_by = issue_numbers(issue.get("blockedBy"))
    blocking = issue_numbers(issue.get("blocking"))

    result.facts.append(f"type={kind or 'unknown'}")
    if subissues:
        result.facts.append("sub-issues=" + ", ".join(f"#{node['number']}" for node in subissues))
    if blocked_by:
        result.facts.append("blocked_by=" + ", ".join(f"#{number}" for number in blocked_by))
    if blocking:
        result.facts.append("blocking=" + ", ".join(f"#{number}" for number in blocking))
    duplicate = issue.get("duplicateOf")
    if duplicate:
        result.facts.append(f"duplicate_of=#{duplicate['number']}")

    if kind is None:
        result.findings.append(
            Finding("warning", "TITLE-TYPE", "标题缺少受支持的 Issue 类型前缀。")
        )

    if kind == "Feature":
        acceptance = [
            node
            for node in subissues
            if issue_type(str(node.get("title", ""))) == "Acceptance"
        ]
        delivery = [
            node
            for node in subissues
            if issue_type(str(node.get("title", ""))) != "Acceptance"
        ]
        if not delivery:
            result.findings.append(
                Finding("error", "FEATURE-DELIVERY", "Feature 缺少交付子 Issue。")
            )
        if len(acceptance) != 1:
            result.findings.append(
                Finding(
                    "error",
                    "FEATURE-ACCEPTANCE",
                    f"Feature 必须有 1 个验收子 Issue；当前为 {len(acceptance)} 个。",
                )
            )
        child_numbers = {int(node["number"]) for node in subissues}
        repeated = referenced_issue_numbers(body) & child_numbers
        if len(repeated) >= 2:
            result.findings.append(
                Finding(
                    "error",
                    "FEATURE-CHILD-LIST",
                    "父 Feature 正文重复列出了多个子 Issue；请使用原生 sub-issues。",
                )
            )

    if kind == "Acceptance":
        parent = issue.get("parent")
        if not parent:
            result.findings.append(
                Finding("error", "ACCEPTANCE-PARENT", "Acceptance 缺少父 Feature。")
            )
        else:
            siblings = [
                node
                for node in nodes(parent.get("subIssues"))
                if int(node["number"]) != int(issue["number"])
                and issue_type(str(node.get("title", ""))) != "Acceptance"
            ]
            required = {int(node["number"]) for node in siblings}
            missing = sorted(required - set(blocked_by))
            if missing:
                result.findings.append(
                    Finding(
                        "error",
                        "ACCEPTANCE-BLOCKERS",
                        "Acceptance 缺少交付子 Issue 的 blocked_by："
                        + ", ".join(f"#{number}" for number in missing),
                    )
                )

    if kind == "Research":
        source = section(body, "来源 Discussion")
        discussions = sorted(set(DISCUSSION_RE.findall(source)))
        has_none = bool(re.search(r"(?m)^\s*(?:[-*]\s*)?无\s*$", source))
        if len(discussions) > 1:
            result.findings.append(
                Finding(
                    "error",
                    "RESEARCH-SOURCE-MULTIPLE",
                    "Research 只能有 1 个活跃来源 Discussion。",
                )
            )
        elif not discussions and not has_none:
            result.findings.append(
                Finding(
                    "error",
                    "RESEARCH-SOURCE-MISSING",
                    "Research 的“来源 Discussion”章节必须写 Discussion 链接或“无”。",
                )
            )

    return result


def audit_pr(pull_request: dict[str, Any]) -> AuditResult:
    result = AuditResult(
        subject=f"PR #{pull_request['number']}",
        title=str(pull_request.get("title", "")),
        url=str(pull_request.get("url", "")),
    )
    body = str(pull_request.get("body") or "")
    matches = TRACKING_RE.findall(body)
    normalized = {match.casefold().replace(" ", " ") for match in matches}
    closes = any(value.startswith("closes") for value in normalized)
    part_of = any(value.startswith("part of") for value in normalized)
    closing_references = nodes(pull_request.get("closingIssuesReferences"))

    result.facts.append(f"closes={str(closes).lower()}")
    result.facts.append(f"part_of={str(part_of).lower()}")
    if closing_references:
        result.facts.append(
            "closing_issues="
            + ", ".join(
                f"{node['repository']['nameWithOwner']}#{node['number']}"
                for node in closing_references
            )
        )

    if not closes and not part_of:
        result.findings.append(
            Finding("error", "PR-TRACKING", "PR 正文必须写 Closes #N 或 Part of #N。")
        )
    if closes and not closing_references:
        result.findings.append(
            Finding(
                "error",
                "PR-CLOSING-REFERENCE",
                "PR 使用 Closes，但没有可识别的关闭 Issue。",
            )
        )
    if len(closing_references) > 1:
        result.findings.append(
            Finding(
                "warning",
                "PR-MULTIPLE-CLOSES",
                "PR 关闭多个 Issue；请人工确认这些 Issue 已完成验收且无法安全拆分。",
            )
        )
    return result


def run_graphql(query: str, variables: dict[str, Any]) -> dict[str, Any]:
    command = ["gh", "api", "graphql", "-f", f"query={query}"]
    for key, value in variables.items():
        command.extend(["-F" if isinstance(value, int) else "-f", f"{key}={value}"])
    process = subprocess.run(command, check=False, capture_output=True, text=True)
    if process.returncode != 0:
        raise RuntimeError(process.stderr.strip() or process.stdout.strip())
    payload = json.loads(process.stdout)
    if payload.get("errors"):
        messages = "; ".join(str(item.get("message", item)) for item in payload["errors"])
        raise RuntimeError(messages)
    return payload


def split_repo(value: str) -> tuple[str, str]:
    parts = value.split("/")
    if len(parts) != 2 or not all(parts):
        raise argparse.ArgumentTypeError("repository must use OWNER/REPO")
    return parts[0], parts[1]


def resolve_repo(explicit: str | None) -> tuple[str, str]:
    if explicit:
        return split_repo(explicit)
    process = subprocess.run(
        ["gh", "repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"],
        check=False,
        capture_output=True,
        text=True,
    )
    if process.returncode != 0:
        raise RuntimeError(process.stderr.strip() or "cannot resolve current repository")
    return split_repo(process.stdout.strip())


def render(results: Iterable[AuditResult]) -> int:
    results = list(results)
    for result in results:
        status = "PASS" if not result.errors else "FAIL"
        print(f"{status} {result.subject} {result.title}")
        for fact in result.facts:
            print(f"  INFO  {fact}")
        for finding in result.findings:
            print(f"  {finding.severity.upper():5} {finding.code}: {finding.message}")
        if result.url:
            print(f"  URL   {result.url}")
    errors = sum(len(result.errors) for result in results)
    warnings = sum(len(result.warnings) for result in results)
    print(f"SUMMARY: {len(results)} subject(s), {errors} error(s), {warnings} warning(s)")
    return 1 if errors else 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", help="GitHub repository in OWNER/REPO form")
    parser.add_argument(
        "--issue", type=int, action="append", default=[], help="Issue number; repeatable"
    )
    parser.add_argument(
        "--pr", type=int, action="append", default=[], help="Pull request number; repeatable"
    )
    args = parser.parse_args(argv)
    if not args.issue and not args.pr:
        parser.error("provide at least one --issue or --pr")
    return args


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    try:
        owner, name = resolve_repo(args.repo)
        results: list[AuditResult] = []
        for number in args.issue:
            payload = run_graphql(
                ISSUE_QUERY, {"owner": owner, "name": name, "number": number}
            )
            issue = payload["data"]["repository"]["issue"]
            if issue is None:
                raise RuntimeError(f"issue #{number} was not found")
            results.append(audit_issue(issue))
        for number in args.pr:
            payload = run_graphql(
                PR_QUERY, {"owner": owner, "name": name, "number": number}
            )
            pull_request = payload["data"]["repository"]["pullRequest"]
            if pull_request is None:
                raise RuntimeError(f"pull request #{number} was not found")
            results.append(audit_pr(pull_request))
    except (RuntimeError, argparse.ArgumentTypeError, json.JSONDecodeError, KeyError, TypeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    return render(results)


if __name__ == "__main__":
    raise SystemExit(main())
