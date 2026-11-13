#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRAMEWORK="${1:-$ROOT/build/kshift-ffi.xcframework}"

python3 - "$ROOT" "$FRAMEWORK" "$(git -C "$ROOT" rev-parse HEAD)" <<'PY'
import hashlib
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
framework = pathlib.Path(sys.argv[2])
current_commit = sys.argv[3]
manifest_path = framework / "build-manifest.json"
if not manifest_path.is_file():
    raise SystemExit(f"missing manifest: {manifest_path}")
manifest = json.loads(manifest_path.read_text())
if manifest.get("source_commit") != current_commit:
    raise SystemExit("artifact source commit does not match current HEAD")
if manifest.get("source_dirty"):
    raise SystemExit("artifact was built from a dirty tracked tree")
artifacts = manifest.get("artifacts", {})
required = {"macos-arm64", "ios-arm64", "ios-simulator-arm64"}
if set(artifacts) != required:
    raise SystemExit(f"artifact targets differ: {sorted(artifacts)}")
commits = {value.get("source_commit") for value in artifacts.values()}
if commits != {current_commit}:
    raise SystemExit("artifact target commits are not identical")
for name, artifact in artifacts.items():
    path = root / artifact["path"]
    if not path.is_file():
        raise SystemExit(f"missing artifact {name}: {path}")
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if digest != artifact["sha256"]:
        raise SystemExit(f"artifact digest mismatch: {name}")
info = framework / "Info.plist"
if not info.is_file():
    raise SystemExit(f"missing XCFramework Info.plist: {info}")
print(f"verified {framework}")
print(f"source_commit={current_commit}")
for name in sorted(artifacts):
    print(f"{name} sha256={artifacts[name]['sha256']}")
PY
