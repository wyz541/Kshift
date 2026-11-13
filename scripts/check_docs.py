#!/usr/bin/env python3
"""Check Kshift R0 Markdown structure without third-party Python packages."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[1]
DOC_DIRS = [ROOT / "docs"]
REQUIRED_FILES = [
    ROOT / "README.md",
    ROOT / "CONTRIBUTING.md",
    ROOT / "docs/spec/kshift-spec-v0.1.md",
    ROOT / "docs/spec/traceability.md",
    ROOT / "docs/decisions/decision-register.md",
    ROOT / "docs/decisions/open-questions.md",
    ROOT / "docs/adr/README.md",
    ROOT / "docs/contracts/README.md",
    ROOT / "proto/kshift/v1/kshift.proto",
    ROOT / "buf.yaml",
    ROOT / "schemas/release-manifest.schema.json",
    ROOT / "schemas/release-fragment.schema.json",
    ROOT / "schemas/examples/release-manifest.example.json",
    ROOT / "schemas/examples/release-fragment.example.json",
]
FRONT_KEYS = {"slug", "title", "type", "status", "updated", "keywords", "description"}
LINK_RE = re.compile(r"(?<!!)\[[^\]]*\]\(([^)]+)\)")
FENCE_RE = re.compile(r"^```([^\n`]*)$")

errors: list[str] = []
slugs: dict[str, Path] = {}


def markdown_files() -> list[Path]:
    files = [ROOT / "README.md", ROOT / "CONTRIBUTING.md", ROOT / ".github/pull_request_template.md"]
    for directory in DOC_DIRS:
        if directory.exists():
            files.extend(directory.rglob("*.md"))
    return sorted({path for path in files if path.exists()})


def parse_front_matter(path: Path) -> dict[str, object] | None:
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0].strip() != "---":
        return None
    try:
        end = next(index for index, line in enumerate(lines[1:], 1) if line.strip() == "---")
    except StopIteration:
        errors.append(f"{path.relative_to(ROOT)}: unterminated YAML front matter")
        return None
    data: dict[str, object] = {}
    current: str | None = None
    for line in lines[1:end]:
        if line.startswith("  - ") and current:
            if not isinstance(data.get(current), list):
                data[current] = []
            cast = data[current]
            cast.append(line[4:].strip())
            continue
        if ":" not in line:
            errors.append(f"{path.relative_to(ROOT)}: invalid front matter line: {line}")
            continue
        key, value = line.split(":", 1)
        current = key.strip()
        value = value.strip().strip('"')
        data[current] = value
    return data


def check_markdown(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    rel = path.relative_to(ROOT)
    in_fence = False
    h1: list[str] = []
    for line_no, line in enumerate(lines, 1):
        if FENCE_RE.match(line):
            if in_fence:
                in_fence = False
            else:
                language = FENCE_RE.match(line).group(1).strip()  # type: ignore[union-attr]
                if not language:
                    errors.append(f"{rel}:{line_no}: fenced code block has no language")
                in_fence = True
            continue
        if not in_fence and line.startswith("# "):
            h1.append(line[2:].strip())
        if not in_fence:
            for match in LINK_RE.finditer(line):
                raw = match.group(1).strip()
                target = raw.split(" ", 1)[0].strip("<>")
                if target.startswith(("http://", "https://", "mailto:", "#")):
                    continue
                target_path = unquote(target.split("#", 1)[0])
                if not target_path:
                    continue
                candidate = (path.parent / target_path).resolve()
                if not candidate.exists():
                    errors.append(f"{rel}:{line_no}: broken relative link {target}")
    if in_fence:
        errors.append(f"{rel}: unterminated fenced code block")
    if rel.as_posix() != ".github/pull_request_template.md" and len(h1) != 1:
        errors.append(f"{rel}: expected exactly one level-1 heading, found {len(h1)}")
    if rel.parts[0] in {"docs", ".github"}:
        front = parse_front_matter(path)
        if rel.as_posix() != ".github/pull_request_template.md":
            if front is None:
                errors.append(f"{rel}: missing front matter")
            else:
                missing = sorted(FRONT_KEYS - set(front))
                if missing:
                    errors.append(f"{rel}: missing front matter keys: {', '.join(missing)}")
                slug = str(front.get("slug", ""))
                if slug:
                    if slug in slugs:
                        errors.append(f"{rel}: duplicate slug {slug} also used by {slugs[slug]}")
                    slugs[slug] = rel
                keywords = front.get("keywords", [])
                if not isinstance(keywords, list) or not 3 <= len(keywords) <= 8:
                    errors.append(f"{rel}: keywords must contain 3 to 8 entries")
                title = str(front.get("title", ""))
                if h1 and title and h1[0] != title:
                    errors.append(f"{rel}: front matter title does not match H1")


def main() -> int:
    for path in REQUIRED_FILES:
        if not path.exists():
            errors.append(f"missing required file: {path.relative_to(ROOT)}")
    for path in markdown_files():
        check_markdown(path)
    for path in sorted((ROOT / "schemas").rglob("*.json")):
        try:
            json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            errors.append(f"{path.relative_to(ROOT)}: invalid JSON: {exc}")
    if errors:
        print("\n".join(f"ERROR: {item}" for item in errors), file=sys.stderr)
        return 1
    print(f"docs: {len(markdown_files())} Markdown files checked")
    print(f"json: {len(list((ROOT / 'schemas').rglob('*.json')))} JSON files parsed")
    print(f"slugs: {len(slugs)} unique slugs")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
