#!/bin/zsh
set -euo pipefail

: "${TEST_DATABASE_URL:?TEST_DATABASE_URL must point to a disposable PostgreSQL 18 maintenance database}"

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
rust_bin="$HOME/.rustup/toolchains/stable-aarch64-apple-darwin/bin"
cargo_bin="${KSHIFT_CARGO:-$rust_bin/cargo}"
export PATH="$rust_bin:$PATH"
duration="${KSHIFT_LOAD_DURATION_SECS:-${1:-1800}}"
wave_interval_ms="${KSHIFT_LOAD_WAVE_INTERVAL_MS:-1000}"
report="${KSHIFT_LOAD_REPORT:-${TMPDIR:-/tmp}/kshift-load-report-$(date +%Y%m%dT%H%M%SZ).json}"
mkdir -p "$(dirname "$report")"

if [[ ! -x "$cargo_bin" ]]; then
  echo "missing cargo binary: $cargo_bin" >&2
  exit 1
fi

KSHIFT_LOAD_DURATION_SECS="$duration" \
KSHIFT_LOAD_WAVE_INTERVAL_MS="$wave_interval_ms" \
KSHIFT_LOAD_REPORT="$report" \
TEST_DATABASE_URL="$TEST_DATABASE_URL" \
  "$cargo_bin" test --locked -p kshift-server --test load_integration -- --nocapture

jq -e '
  .status == "passed"
  and .persistent_network_clients >= 100
  and .persistent_network_event_streams >= 64
  and .network_end_health_failures == 0
  and .network_event_stream_errors == 0
  and .network_event_stream_unexpected_closes == 0
  and .network_event_gaps == 0
  and .network_received_event_deliveries == .network_expected_event_deliveries
' "$report" >/dev/null
printf 'load_report=%s\n' "$report"
