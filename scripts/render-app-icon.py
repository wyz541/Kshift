#!/usr/bin/env python3
"""Render the Kshift app icon from Assets/AppIcon/AppIcon.svg.

The SVG holds the full-bleed 1024pt artwork between the ART markers. This
script wraps that artwork for iOS (full bleed) and macOS (824pt squircle with
a drop shadow), rasterizes both with headless Chrome, and exports every size
required by the two app icon asset catalogs.

Usage: python3 scripts/render-app-icon.py
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import urllib.parse
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Assets" / "AppIcon" / "AppIcon.svg"
IOS_SET = ROOT / "Apps" / "KshiftIOS" / "Assets.xcassets" / "AppIcon.appiconset"
MAC_SET = ROOT / "Apps" / "KshiftMacOS" / "Assets.xcassets" / "AppIcon.appiconset"
PREVIEW = ROOT / "Assets" / "AppIcon" / "preview.png"

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
CANVAS = 1024
MAC_CONTENT = 824
MAC_RADIUS = 185

MAC_SIZES = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]


def extract_art() -> str:
    text = SOURCE.read_text(encoding="utf-8")
    start = text.index("<!-- ART:BEGIN -->") + len("<!-- ART:BEGIN -->")
    end = text.index("<!-- ART:END -->")
    return text[start:end]


def write_svgs(art: str, directory: Path) -> tuple[Path, Path]:
    ios = (
        '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" '
        'viewBox="0 0 1024 1024">'
        + art
        + "</svg>"
    )
    scale = MAC_CONTENT / CANVAS
    offset = (CANVAS - MAC_CONTENT) / 2
    mac = (
        '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" '
        'viewBox="0 0 1024 1024">'
        "<defs>"
        f'<clipPath id="macBody"><rect x="{offset}" y="{offset}" '
        f'width="{MAC_CONTENT}" height="{MAC_CONTENT}" rx="{MAC_RADIUS}"/></clipPath>'
        '<filter id="macShadow" x="-20%" y="-20%" width="140%" height="145%">'
        '<feDropShadow dx="0" dy="10" stdDeviation="16" flood-color="#000000" '
        'flood-opacity="0.3"/></filter>'
        "</defs>"
        '<g filter="url(#macShadow)"><g clip-path="url(#macBody)">'
        f'<g transform="translate({offset} {offset}) scale({scale:.9f})">'
        + art
        + "</g></g></g></svg>"
    )
    ios_path = directory / "icon-ios.svg"
    mac_path = directory / "icon-macos.svg"
    ios_path.write_text(ios, encoding="utf-8")
    mac_path.write_text(mac, encoding="utf-8")
    return ios_path, mac_path


def render(svg: Path, png: Path, work: Path) -> None:
    args = [
        CHROME,
        "--headless=new",
        "--disable-gpu",
        "--hide-scrollbars",
        "--no-first-run",
        "--disable-extensions",
        "--disable-background-networking",
        "--force-device-scale-factor=1",
        "--default-background-color=00000000",
        f"--user-data-dir={work / 'chrome-profile'}",
        f"--window-size={CANVAS},{CANVAS}",
        "--virtual-time-budget=1500",
        f"--screenshot={png}",
        svg.as_uri(),
    ]
    subprocess.run(args, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if not png.exists():
        raise RuntimeError(f"Chrome did not write {png}")


def save_square(image: Image.Image, size: int, destination: Path, alpha: bool) -> None:
    resized = image.resize((size, size), Image.LANCZOS)
    if alpha:
        resized.save(destination, optimize=True)
    else:
        if resized.mode != "RGB":
            resized = resized.convert("RGB")
        resized.save(destination, optimize=True)


def build_preview(ios_master: Image.Image, mac_master: Image.Image) -> None:
    width, height = 1680, 760
    sheet = Image.new("RGB", (width, height), (238, 241, 246))
    mac_square = Image.new("RGBA", (CANVAS, CANVAS), (238, 241, 246, 255))
    mac_square.alpha_composite(mac_master)
    ios_512 = ios_master.resize((512, 512), Image.LANCZOS)
    mac_512 = mac_square.resize((512, 512), Image.LANCZOS)
    sheet.paste(ios_512, (80, 60))
    sheet.paste(mac_512.convert("RGB"), (700, 60))
    small_sizes = [(128, 600), (64, 600), (32, 600)]
    x = 80
    for size, y in small_sizes:
        icon = mac_square.resize((size, size), Image.LANCZOS)
        transparent = Image.new("RGBA", (size, size), (238, 241, 246, 255))
        transparent.alpha_composite(icon)
        sheet.paste(transparent.convert("RGB"), (x, y))
        x += size + 40
    sheet.save(PREVIEW, optimize=True)


def main() -> int:
    if not SOURCE.exists():
        print(f"missing source: {SOURCE}", file=sys.stderr)
        return 1
    if not Path(CHROME).exists():
        print(f"missing Chrome: {CHROME}", file=sys.stderr)
        return 1

    IOS_SET.mkdir(parents=True, exist_ok=True)
    MAC_SET.mkdir(parents=True, exist_ok=True)

    art = extract_art()
    work = Path(tempfile.mkdtemp(prefix="kshift-icon-"))
    try:
        ios_svg, mac_svg = write_svgs(art, work)
        ios_png = work / "icon-ios.png"
        mac_png = work / "icon-macos.png"
        render(ios_svg, ios_png, work)
        render(mac_svg, mac_png, work)

        ios_master = Image.open(ios_png).convert("RGB")
        mac_master = Image.open(mac_png).convert("RGBA")

        save_square(ios_master, CANVAS, IOS_SET / "AppIcon-1024.png", alpha=False)
        for filename, size in MAC_SIZES:
            save_square(mac_master, size, MAC_SET / filename, alpha=True)

        build_preview(ios_master, mac_master)

        print(f"iOS  master: {IOS_SET / 'AppIcon-1024.png'}")
        print(f"macOS set:   {MAC_SET} ({len(MAC_SIZES)} sizes)")
        print(f"preview:     {PREVIEW}")
    finally:
        shutil.rmtree(work, ignore_errors=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
