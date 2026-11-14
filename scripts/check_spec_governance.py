#!/usr/bin/env python3
"""Check the Spec-first governance migration without third-party packages."""
from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
INDEX = ROOT / "docs/specs/index.md"
GOVERNANCE = ROOT / "docs/specs/governance.md"
CURRENT_SPEC = ROOT / "docs/spec/kshift-spec-v0.1.md"
PR_TEMPLATE = ROOT / ".github/pull_request_template.md"
CONTRIBUTING = ROOT / "CONTRIBUTING.md"


def front_matter_status(path: pathlib.Path) -> str | None:
    lines = path.read_text().splitlines()
    if not lines or lines[0].strip() != "---":
        return None
    for line in lines[1:]:
        if line.strip() == "---":
            return None
        if line.startswith("status:"):
            return line.split(":", 1)[1].strip().strip('"')
    return None


def main() -> int:
    errors: list[str] = []
    required = [
        INDEX,
        GOVERNANCE,
        CURRENT_SPEC,
        PR_TEMPLATE,
        CONTRIBUTING,
        ROOT / "docs/decisions/decision-register.md",
        ROOT / "docs/decisions/open-questions.md",
    ]
    for path in required:
        if not path.is_file():
            errors.append(f"missing required file: {path.relative_to(ROOT)}")

    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1

    if front_matter_status(INDEX) != "active":
        errors.append("docs/specs/index.md: status must be active")
    if front_matter_status(GOVERNANCE) != "active":
        errors.append("docs/specs/governance.md: status must be active")
    for relative in ("docs/decisions/decision-register.md", "docs/decisions/open-questions.md"):
        if front_matter_status(ROOT / relative) != "superseded":
            errors.append(f"{relative}: status must be superseded")

    index_text = INDEX.read_text()
    adr_files = sorted((ROOT / "docs/adr").glob("0[0-9][0-9][0-9]-*.md"))
    if len(adr_files) != 10:
        errors.append(f"expected 10 ADR files, found {len(adr_files)}")
    for adr_file in adr_files:
        match = re.match(r"(\d{4})-", adr_file.name)
        if not match:
            errors.append(f"invalid ADR filename: {adr_file.name}")
            continue
        adr_id = f"ADR-{match.group(1)}"
        if index_text.count(f"| {adr_id} |") != 1:
            errors.append(f"docs/specs/index.md: {adr_id} must have one migration row")
        if front_matter_status(adr_file) != "superseded":
            errors.append(f"{adr_file.relative_to(ROOT)}: status must be superseded")

    if "| `KS-GOV` | [governance.md](governance.md) | `active` |" not in index_text:
        errors.append("docs/specs/index.md: KS-GOV active row is missing")

    current_spec = CURRENT_SPEC.read_text()
    if "## 14. 项目治理" not in current_spec or "[KS-GOV](../specs/governance.md)" not in current_spec:
        errors.append("docs/spec/kshift-spec-v0.1.md: governance must point to KS-GOV")
    if re.search(r"^- `GOV-0\d\d`：", current_spec, re.MULTILINE):
        errors.append("docs/spec/kshift-spec-v0.1.md: legacy governance rules must move out")

    pr_template = PR_TEMPLATE.read_text()
    if "- Active Spec:" not in pr_template or "- Decision Issue:" not in pr_template:
        errors.append("PR template must require Active Spec and Decision Issue")
    if re.search(r"(?m)^- (?:Decision|ADR):", pr_template):
        errors.append("PR template must not use Decision or ADR as a current authority field")

    contributing = CONTRIBUTING.read_text()
    if "ADR 不在权威顺序中" not in contributing:
        errors.append("CONTRIBUTING.md must state that ADR is historical")
    if "禁止为新决策创建 ADR" not in contributing:
        errors.append("CONTRIBUTING.md must prohibit new ADRs")

    for form in sorted((ROOT / ".github/ISSUE_TEMPLATE").glob("*.yml")):
        text = form.read_text()
        if "Decision/ADR" in text or re.search(r"(?m)^\s+- ADR：", text):
            errors.append(f"{form.relative_to(ROOT)}: still depends on ADR")

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1

    print("Spec-first governance: OK")
    print("Active specs: KS-GOV")
    print("Historical ADRs: 10 superseded")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
