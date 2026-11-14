#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def source_files() -> list[pathlib.Path]:
    files = [ROOT / "Makefile", ROOT / "README.md", ROOT / "CONTRIBUTING.md"]
    files.extend(sorted((ROOT / "docs").rglob("*.md")))
    files.extend(sorted((ROOT / "scripts").glob("*.sh")))
    return [path for path in files if path.is_file()]


def command_blocks(path: pathlib.Path) -> list[tuple[int, str]]:
    lines = path.read_text().splitlines()
    blocks: list[tuple[int, str]] = []
    index = 0
    while index < len(lines):
        line = lines[index]
        if not line.lstrip().startswith("xcodebuild"):
            index += 1
            continue
        start = index + 1
        block = line
        while block.rstrip().endswith("\\") and index + 1 < len(lines):
            index += 1
            block += "\n" + lines[index]
        blocks.append((start, block))
        index += 1
    return blocks


def defines_fixed_path(text: str) -> bool:
    return "build/DerivedData" in text or (
        "BUILD_DIR := $(CURDIR)/build" in text
        and "DERIVED_DATA := $(BUILD_DIR)/DerivedData" in text
    )


def main() -> int:
    errors: list[str] = []
    files = source_files()

    for path in files:
        text = path.read_text()
        relative = path.relative_to(ROOT)
        for line_number, block in command_blocks(path):
            if "-create-xcframework" in block:
                continue
            if "-derivedDataPath" not in block:
                errors.append(
                    f"{relative}:{line_number}: xcodebuild command has no -derivedDataPath"
                )
            if not defines_fixed_path(text):
                errors.append(
                    f"{relative}:{line_number}: file does not define build/DerivedData"
                )

    project = (ROOT / "project.yml").read_text()
    required_project_values = (
        "Kshift-macOS",
        "Kshift-iOS",
        "com.wyz541.kshift.mac",
        "com.wyz541.kshift.ios",
    )
    for value in required_project_values:
        if value not in project:
            errors.append(f"project.yml: missing stable value {value}")

    debug_display_names = re.findall(
        r"^\s*INFOPLIST_KEY_CFBundleDisplayName: Kshift Dev\s*$", project, re.MULTILINE
    )
    release_display_names = re.findall(
        r"^\s*INFOPLIST_KEY_CFBundleDisplayName: Kshift\s*$", project, re.MULTILINE
    )
    if len(debug_display_names) != 2:
        errors.append("project.yml: Debug display name must be Kshift Dev on both apps")
    if len(release_display_names) < 2:
        errors.append("project.yml: Release display name must be Kshift on both apps")

    application_copy = re.compile(
        r"(?:^\s*|[;&|]\s*)(?:cp|ditto|rsync)\b.*(?:/Applications|~/Applications)"
    )
    destructive_find = re.compile(r"\bfind\b.*Kshift.*(?:-delete|-exec\s+rm)")
    for path in [ROOT / "Makefile", *sorted((ROOT / "scripts").glob("*.sh"))]:
        text = path.read_text()
        relative = path.relative_to(ROOT)
        for line_number, line in enumerate(text.splitlines(), 1):
            if application_copy.search(line):
                errors.append(
                    f"{relative}:{line_number}: copies a build into Applications"
                )
            if destructive_find.search(line):
                errors.append(
                    f"{relative}:{line_number}: deletes build products by name search"
                )

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1

    print(f"Verified build governance in {len(files)} files.")
    print("DerivedData: build/DerivedData")
    print("Stable targets: Kshift-macOS, Kshift-iOS")
    print("Stable bundle IDs: com.wyz541.kshift.mac, com.wyz541.kshift.ios")
    print("Debug display name: Kshift Dev")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
