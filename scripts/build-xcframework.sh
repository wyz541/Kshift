#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/build"
OUTPUT="$BUILD_DIR/kshift-ffi.xcframework"
HEADERS="$ROOT/include"

cd "$ROOT"

if command -v cargo >/dev/null 2>&1; then
  CARGO=(cargo)
elif command -v rustup >/dev/null 2>&1; then
  export RUSTUP_TOOLCHAIN=stable
  export PATH="$(dirname "$(rustup which rustc)"):$PATH"
  CARGO=(cargo)
else
  echo "cargo or rustup is required" >&2
  exit 1
fi

for target in aarch64-apple-darwin aarch64-apple-ios aarch64-apple-ios-sim; do
  if ! rustup target list --installed | grep -qx "$target"; then
    echo "missing Rust target: $target" >&2
    exit 1
  fi
done

export MACOSX_DEPLOYMENT_TARGET=26.0
export IPHONEOS_DEPLOYMENT_TARGET=26.0

"${CARGO[@]}" build --locked -p kshift-ffi --release --target aarch64-apple-darwin
"${CARGO[@]}" build --locked -p kshift-ffi --release --target aarch64-apple-ios
"${CARGO[@]}" build --locked -p kshift-ffi --release --target aarch64-apple-ios-sim

mkdir -p "$BUILD_DIR"
if [[ -e "$OUTPUT" ]]; then
  mv "$OUTPUT" "$BUILD_DIR/kshift-ffi-previous-$(date -u +%Y%m%dT%H%M%SZ)"
fi

xcodebuild -create-xcframework \
  -library "$ROOT/target/aarch64-apple-darwin/release/libkshift_ffi.a" \
  -headers "$HEADERS" \
  -library "$ROOT/target/aarch64-apple-ios/release/libkshift_ffi.a" \
  -headers "$HEADERS" \
  -library "$ROOT/target/aarch64-apple-ios-sim/release/libkshift_ffi.a" \
  -headers "$HEADERS" \
  -output "$OUTPUT"

SOURCE_COMMIT="$(git rev-parse HEAD)"
SOURCE_DIRTY=0
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  SOURCE_DIRTY=1
fi

python3 - "$ROOT" "$OUTPUT" "$SOURCE_COMMIT" "$SOURCE_DIRTY" <<'PY'
import datetime
import hashlib
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
output = pathlib.Path(sys.argv[2])
source_commit = sys.argv[3]
source_dirty = bool(int(sys.argv[4]))
targets = [
    ("macos-arm64", root / "target/aarch64-apple-darwin/release/libkshift_ffi.a"),
    ("ios-arm64", root / "target/aarch64-apple-ios/release/libkshift_ffi.a"),
    ("ios-simulator-arm64", root / "target/aarch64-apple-ios-sim/release/libkshift_ffi.a"),
]
artifacts = {}
for name, path in targets:
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    artifacts[name] = {
        "path": str(path.relative_to(root)),
        "sha256": digest,
        "source_commit": source_commit,
    }
manifest = {
    "schema_version": 1,
    "generated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "source_commit": source_commit,
    "source_dirty": source_dirty,
    "xcframework": str(output.relative_to(root)),
    "artifacts": artifacts,
}
(output / "build-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(json.dumps(manifest, indent=2))
PY

echo "XCFramework: $OUTPUT"
