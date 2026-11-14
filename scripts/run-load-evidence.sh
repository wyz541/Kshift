#!/bin/zsh
set -euo pipefail

: "${TEST_DATABASE_URL:?TEST_DATABASE_URL must point to a disposable PostgreSQL 18 maintenance database}"

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
rust_bin="$HOME/.rustup/toolchains/stable-aarch64-apple-darwin/bin"
cargo_bin="${KSHIFT_CARGO:-$rust_bin/cargo}"
export PATH="$rust_bin:$PATH"
duration="${KSHIFT_LOAD_DURATION_SECS:-${1:-1800}}"
report="${KSHIFT_LOAD_REPORT:-${TMPDIR:-/tmp}/kshift-load-report-$(date +%Y%m%dT%H%M%SZ).json}"
mkdir -p "$(dirname "$report")"

if [[ ! -x "$cargo_bin" ]]; then
  echo "missing cargo binary: $cargo_bin" >&2
  exit 1
fi

KSHIFT_LOAD_DURATION_SECS="$duration" \
KSHIFT_LOAD_REPORT="$report" \
TEST_DATABASE_URL="$TEST_DATABASE_URL" \
  "$cargo_bin" test --locked -p kshift-server --test load_integration -- --nocapture

printf 'load_report=%s\n' "$report"
