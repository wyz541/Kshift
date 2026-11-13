#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/build/swift-smoke"
mkdir -p "$BUILD_DIR"

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

export MACOSX_DEPLOYMENT_TARGET=26.0
"${CARGO[@]}" build --locked -p kshift-ffi
"${CARGO[@]}" build --locked -p kshift-client --example mock_server

READY_FILE="$BUILD_DIR/server-ready.txt"
SERVER_LOG="$BUILD_DIR/server.log"
SMOKE_BINARY="$BUILD_DIR/KshiftFFISmoke"
if [[ -e "$READY_FILE" ]]; then
  mv "$READY_FILE" "$BUILD_DIR/server-ready-previous.txt"
fi

"$ROOT/target/debug/examples/mock_server" \
  --cert "$ROOT/fixtures/tls/server.pem" \
  --key "$ROOT/fixtures/tls/server-key.pem" \
  --ready-file "$READY_FILE" \
  >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!
cleanup() {
  kill "$SERVER_PID" 2>/dev/null || true
  wait "$SERVER_PID" 2>/dev/null || true
}
trap cleanup EXIT

for _ in $(seq 1 100); do
  if [[ -s "$READY_FILE" ]]; then
    break
  fi
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    cat "$SERVER_LOG" >&2
    exit 1
  fi
  sleep 0.1
done
if [[ ! -s "$READY_FILE" ]]; then
  cat "$SERVER_LOG" >&2
  echo "mock server did not become ready" >&2
  exit 1
fi
ENDPOINT="$(head -n 1 "$READY_FILE")"

swiftc \
  -target arm64-apple-macos26.0 \
  -I "$ROOT/include" \
  "$ROOT/Sources/KshiftFFI/KshiftRustClient.swift" \
  "$ROOT/swift-tests/KshiftFFISmoke/main.swift" \
  -L "$ROOT/target/debug" \
  -lkshift_ffi \
  -o "$SMOKE_BINARY"

"$SMOKE_BINARY" --endpoint "$ENDPOINT" --ca "$ROOT/fixtures/tls/ca.pem"
