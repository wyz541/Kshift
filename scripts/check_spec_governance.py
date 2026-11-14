#!/usr/bin/env python3
"""Check the Spec-first migration without third-party packages."""
from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
INDEX = ROOT / "docs/specs/index.md"
LEGACY_SPEC = ROOT / "docs/spec/kshift-spec-v0.1.md"
PR_TEMPLATE = ROOT / ".github/pull_request_template.md"
CONTRIBUTING = ROOT / "CONTRIBUTING.md"
PROTOCOL_CONTRACT = ROOT / "docs/contracts/protocol-v0.1.md"
RELEASE_CONTRACT = ROOT / "docs/contracts/release-v0.1.md"

SPECS = {
    "KS-CORE": "docs/specs/core.md",
    "KS-DOMAIN": "docs/specs/domain.md",
    "KS-ARCH": "docs/specs/architecture.md",
    "KS-OPS": "docs/specs/operations.md",
    "KS-UI": "docs/specs/ui.md",
    "KS-RELEASE": "docs/specs/release.md",
    "KS-GOV": "docs/specs/governance.md",
}

ADR_TARGETS = {
    "ADR-0001": "KS-ARCH",
    "ADR-0002": "KS-UI",
    "ADR-0003": "KS-UI",
    "ADR-0004": "KS-OPS",
    "ADR-0005": "KS-ARCH",
    "ADR-0006": "KS-ARCH",
    "ADR-0007": "KS-RELEASE",
    "ADR-0008": "KS-DOMAIN",
    "ADR-0009": "KS-UI",
    "ADR-0010": "KS-GOV",
}

RULE_RE = re.compile(r"^\s*-\s+`([A-Z][A-Z0-9]*(?:-[A-Z0-9]+)+)`：(.+)$")


def front_matter(path: pathlib.Path) -> dict[str, str] | None:
    lines = path.read_text().splitlines()
    if not lines or lines[0].strip() != "---":
        return None
    data: dict[str, str] = {}
    for line in lines[1:]:
        if line.strip() == "---":
            return data
        if ":" in line and not line.startswith(" "):
            key, value = line.split(":", 1)
            data[key.strip()] = value.strip().strip('"')
    return None


def normalized_rule_text(text: str) -> str:
    return re.sub(r"\s+", "", text.replace("`", "").replace("：", ":"))


def main() -> int:
    errors: list[str] = []
    required = [
        INDEX,
        LEGACY_SPEC,
        PR_TEMPLATE,
        CONTRIBUTING,
        PROTOCOL_CONTRACT,
        RELEASE_CONTRACT,
        ROOT / "docs/decisions/decision-register.md",
        ROOT / "docs/decisions/open-questions.md",
        *[ROOT / relative for relative in SPECS.values()],
    ]
    for path in required:
        if not path.is_file():
            errors.append(f"missing required file: {path.relative_to(ROOT)}")

    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1

    index_front = front_matter(INDEX)
    if not index_front or index_front.get("status") != "active":
        errors.append("docs/specs/index.md: status must be active")
    index_text = INDEX.read_text()

    seen_ids: dict[str, pathlib.Path] = {}
    seen_texts: dict[str, tuple[str, pathlib.Path]] = {}
    for spec_id, relative in SPECS.items():
        path = ROOT / relative
        meta = front_matter(path)
        if not meta:
            errors.append(f"{relative}: missing front matter")
            continue
        if meta.get("status") != "active":
            errors.append(f"{relative}: status must be active")
        if not meta.get("owner"):
            errors.append(f"{relative}: owner is required")
        expected_row = f"| `{spec_id}` | [{path.name}]({path.name}) |"
        if expected_row not in index_text:
            errors.append(f"docs/specs/index.md: missing active row for {spec_id}")
        for line in path.read_text().splitlines():
            match = RULE_RE.match(line)
            if not match:
                continue
            rule_id, rule_text = match.groups()
            if rule_id in seen_ids:
                errors.append(
                    f"duplicate rule ID {rule_id}: {seen_ids[rule_id].relative_to(ROOT)} and {relative}"
                )
            else:
                seen_ids[rule_id] = path
            normalized = normalized_rule_text(rule_text)
            if normalized in seen_texts:
                other_id, other_path = seen_texts[normalized]
                errors.append(
                    f"duplicate rule text {other_id}/{rule_id}: "
                    f"{other_path.relative_to(ROOT)} and {relative}"
                )
            else:
                seen_texts[normalized] = (rule_id, path)

    legacy_meta = front_matter(LEGACY_SPEC)
    if not legacy_meta or legacy_meta.get("status") != "historical":
        errors.append("docs/spec/kshift-spec-v0.1.md: status must be historical")
    legacy_text = LEGACY_SPEC.read_text()
    if "[Active Spec 索引](../specs/index.md)" not in legacy_text:
        errors.append("legacy Spec must link to the Active Spec index")
    for line in legacy_text.splitlines():
        if RULE_RE.match(line):
            errors.append("legacy Spec still contains a current rule definition")
            break

    for relative in ("docs/decisions/decision-register.md", "docs/decisions/open-questions.md"):
        meta = front_matter(ROOT / relative)
        if not meta or meta.get("status") != "superseded":
            errors.append(f"{relative}: status must be superseded")

    adr_files = sorted((ROOT / "docs/adr").glob("0[0-9][0-9][0-9]-*.md"))
    if len(adr_files) != 10:
        errors.append(f"expected 10 ADR files, found {len(adr_files)}")
    for adr_file in adr_files:
        match = re.match(r"(\d{4})-", adr_file.name)
        if not match:
            errors.append(f"invalid ADR filename: {adr_file.name}")
            continue
        adr_id = f"ADR-{match.group(1)}"
        target_id = ADR_TARGETS.get(adr_id)
        if not target_id:
            errors.append(f"missing target mapping for {adr_id}")
        elif index_text.count(f"| {adr_id} |") != 1:
            errors.append(f"docs/specs/index.md: {adr_id} must have one migration row")
        if front_matter(adr_file).get("status") != "superseded":  # type: ignore[union-attr]
            errors.append(f"{adr_file.relative_to(ROOT)}: status must be superseded")
        adr_text = adr_file.read_text()
        if target_id and f"[KS-" not in adr_text:
            errors.append(f"{adr_file.relative_to(ROOT)}: missing Active Spec link")

    protocol_text = PROTOCOL_CONTRACT.read_text()
    for link in (
        "[KS-DOMAIN](../specs/domain.md)",
        "[KS-ARCH](../specs/architecture.md)",
        "[KS-OPS](../specs/operations.md)",
    ):
        if link not in protocol_text:
            errors.append(f"protocol contract must link to {link}")
    if "[KS-RELEASE](../specs/release.md)" not in RELEASE_CONTRACT.read_text():
        errors.append("release contract must link to KS-RELEASE")

    pr_text = PR_TEMPLATE.read_text()
    if "- Active Spec:" not in pr_text or "docs/specs/index.md" not in pr_text:
        errors.append("PR template must link the Active Spec index")
    if "- Decision Issue:" not in pr_text:
        errors.append("PR template must require Decision Issue")
    if re.search(r"(?m)^- (?:Decision|ADR):", pr_text):
        errors.append("PR template must not use Decision or ADR as a current authority field")

    contributing = CONTRIBUTING.read_text()
    if "ADR 不在权威顺序中" not in contributing:
        errors.append("CONTRIBUTING.md must state that ADR is historical")
    if "禁止为新决策创建 ADR" not in contributing:
        errors.append("CONTRIBUTING.md must prohibit new ADRs")

    for form in sorted((ROOT / ".github/ISSUE_TEMPLATE").glob("*.yml")):
        text = form.read_text()
        if "docs/specs/index.md" not in text:
            errors.append(f"{form.relative_to(ROOT)}: missing Active Spec index link")
        if "Decision/ADR" in text or re.search(r"(?m)^\s+- ADR：", text):
            errors.append(f"{form.relative_to(ROOT)}: still depends on ADR")

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1

    print("Spec-first governance: OK")
    print(f"Active specs: {len(SPECS)}")
    print(f"Unique rule IDs: {len(seen_ids)}")
    print(f"Unique rule texts: {len(seen_texts)}")
    print("Historical ADRs: 10 superseded")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
