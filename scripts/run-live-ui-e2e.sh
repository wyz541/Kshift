#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

scratch_root="${KSHIFT_LIVE_UI_SCRATCH_ROOT:-$HOME/workspace/scratch/kshift-live-ui-e2e}"
scratch="$scratch_root/$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$scratch"

admin_url="${KSHIFT_LIVE_UI_ADMIN_URL:-postgres://postgres:postgres@127.0.0.1:54329/postgres}"
database_name="kshift_live_ui_$(date +%s)_$$"
database_url="${admin_url%/*}/$database_name"
user_id="11111111-1111-4111-8111-111111111111"
token="live-ui-e2e-token"
ca_path="$root/fixtures/tls/ca.pem"
cert_path="$root/fixtures/tls/server.pem"
key_path="$root/fixtures/tls/server-key.pem"
auth_path="$scratch/auth.json"
server_log="$scratch/server.log"
server_pid=""
port="${KSHIFT_LIVE_UI_PORT:-$(python3 - <<'PY'
import socket
with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
)}"
endpoint="https://localhost:$port"

cleanup() {
  if [[ -n "$server_pid" ]] && kill -0 "$server_pid" 2>/dev/null; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  if command -v psql >/dev/null 2>&1; then
    psql "$admin_url" -v ON_ERROR_STOP=1 -q \
      -c "DROP DATABASE IF EXISTS \"$database_name\" WITH (FORCE)" \
      >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

rust_bin="$HOME/.rustup/toolchains/stable-aarch64-apple-darwin/bin"
cargo_bin="$rust_bin/cargo"
export PATH="$rust_bin:$PATH"
export CARGO_HOME="$root/.build/cargo-home"
mkdir -p "$CARGO_HOME"
if [[ ! -e "$CARGO_HOME/registry" && -d "$HOME/.cargo/registry" ]]; then
  ln -s "$HOME/.cargo/registry" "$CARGO_HOME/registry"
fi
cargo_flags=(--locked)
if [[ "${KSHIFT_CARGO_OFFLINE:-1}" == "1" ]]; then
  cargo_flags+=(--offline)
fi

docker compose up -d --wait postgres >/dev/null
for _ in {1..30}; do
  if pg_isready -h 127.0.0.1 -p 54329 -U postgres >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

psql "$admin_url" -v ON_ERROR_STOP=1 -q -c "CREATE DATABASE \"$database_name\""
"$cargo_bin" build "${cargo_flags[@]}" -p kshift-server >/dev/null
"$cargo_bin" build "${cargo_flags[@]}" -p kshift-client --example live_ui_fixture >/dev/null

export KSHIFT_DATABASE_URL="$database_url"
export KSHIFT_DB_MIN_CONNECTIONS=1
export KSHIFT_DB_MAX_CONNECTIONS=8
"$root/target/debug/kshift-server" migrate >"$scratch/migrate.json"
printf '{"id":"%s","display_name":"Mia Chen","is_admin":true}\n' "$user_id" |
  "$root/target/debug/kshift-server" bootstrap-user

token_hash="$(printf '%s' "$token" | shasum -a 256 | awk '{print $1}')"
cat >"$auth_path" <<EOF
{"tokens":[{"sha256":"$token_hash","user_id":"$user_id"}]}
EOF
chmod 600 "$auth_path"

KSHIFT_DATABASE_URL="$database_url" \
KSHIFT_DB_MIN_CONNECTIONS=1 \
KSHIFT_DB_MAX_CONNECTIONS=8 \
KSHIFT_BIND_ADDR="127.0.0.1:$port" \
KSHIFT_TLS_CERT_PATH="$cert_path" \
KSHIFT_TLS_KEY_PATH="$key_path" \
KSHIFT_AUTH_FILE="$auth_path" \
RUST_LOG="kshift_server=info" \
  "$root/target/debug/kshift-server" serve >"$server_log" 2>&1 &
server_pid=$!

for _ in {1..60}; do
  if ! kill -0 "$server_pid" 2>/dev/null; then
    cat "$server_log" >&2
    exit 1
  fi
  if nc -z 127.0.0.1 "$port" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

KSHIFT_ENDPOINT="$endpoint" \
KSHIFT_CA_PATH="$ca_path" \
KSHIFT_TOKEN="$token" \
KSHIFT_ACTOR_ID="$user_id" \
  "$root/target/debug/examples/live_ui_fixture" --summary-file "$scratch/fixture.json"

xcodegen generate >/dev/null
ios_result="$scratch/ios-live.xcresult"

KSHIFT_ENDPOINT="$endpoint" \
KSHIFT_CA_PATH="$ca_path" \
KSHIFT_TOKEN="$token" \
KSHIFT_ACTOR_ID="$user_id" \
TEST_RUNNER_KSHIFT_ENDPOINT="$endpoint" \
TEST_RUNNER_KSHIFT_CA_PATH="$ca_path" \
TEST_RUNNER_KSHIFT_TOKEN="$token" \
TEST_RUNNER_KSHIFT_ACTOR_ID="$user_id" \
  xcodebuild \
    -project Kshift.xcodeproj \
    -scheme Kshift-iOS \
    -configuration Debug \
    -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
    -only-testing:Kshift-iOS-PlannerUITests/KshiftIOSUITests/testLiveServerHistoryAndWriteE2E \
    -resultBundlePath "$ios_result" \
    test >"$scratch/ios-test.log" 2>&1

create_task_lines="$(rg -c '"command":"create_task"' "$server_log")"
if (( create_task_lines < 6 )); then
  echo "Expected fixture and UI create_task commands in server log." >&2
  exit 1
fi
if ! rg -q '"revision":6' "$server_log"; then
  echo "Expected the UI write to produce snapshot revision 6." >&2
  exit 1
fi

macos_derived="$scratch/macos-derived"
xcodebuild \
  -project Kshift.xcodeproj \
  -scheme Kshift-macOS \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$macos_derived" \
  build >"$scratch/macos-build.log" 2>&1
macos_app="$macos_derived/Build/Products/Debug/Kshift-macOS.app"

run_macos_capture() {
  local output="$1"
  shift
  local log="$scratch/macos-capture-$(basename "$output").log"
  local open_args=(--env "KSHIFT_CAPTURE_PNG=$output")
  local assignment
  for assignment in "$@"; do
    open_args+=(--env "$assignment")
  done
  open -n -W -o "$log" --stderr "$log" "${open_args[@]}" "$macos_app" &
  local open_pid=$!
  local captured=false
  for _ in {1..120}; do
    if [[ -s "$output" ]]; then
      captured=true
      break
    fi
    if ! kill -0 "$open_pid" 2>/dev/null; then
      break
    fi
    sleep 0.5
  done
  if [[ "$captured" != true ]]; then
    pkill -f "$macos_app/Contents/MacOS/Kshift-macOS" >/dev/null 2>&1 || true
    kill "$open_pid" >/dev/null 2>&1 || true
    cat "$log" >&2
    return 1
  fi
  wait "$open_pid" 2>/dev/null || true
}

run_macos_capture "$scratch/macos-board.png" KSHIFT_DEMO_MODE=1
run_macos_capture \
  "$scratch/macos-live-server.png" \
  KSHIFT_USE_FFI=1 \
  KSHIFT_ENDPOINT="$endpoint" \
  KSHIFT_CA_PATH="$ca_path" \
  KSHIFT_TOKEN="$token" \
  KSHIFT_ACTOR_ID="$user_id" \
  KSHIFT_TLS_DOMAIN=localhost

mkdir -p "$scratch/ios-attachments"
xcrun xcresulttool export attachments \
  --path "$ios_result" \
  --output-path "$scratch/ios-attachments" >/dev/null

python3 - "$scratch/ios-attachments/manifest.json" "$scratch/ios-live-server.png" <<'PY'
import json
import pathlib
import shutil
import sys

manifest_path = pathlib.Path(sys.argv[1])
destination = pathlib.Path(sys.argv[2])
manifest = json.loads(manifest_path.read_text())
for suite in manifest:
    for attachment in suite.get("attachments", []):
        name = attachment.get("suggestedHumanReadableName", "")
        if name.startswith("ios-live-server"):
            source = manifest_path.parent / attachment["exportedFileName"]
            shutil.copyfile(source, destination)
            raise SystemExit(0)
raise SystemExit("ios-live-server attachment not found")
PY

cp "$scratch/macos-board.png" "$root/docs/evidence/macos-board.png"
cp "$scratch/macos-live-server.png" "$root/docs/evidence/macos-live-server.png"
cp "$scratch/ios-live-server.png" "$root/docs/evidence/ios-live-server.png"

printf 'scratch=%s\n' "$scratch"
printf 'ios_result=%s\n' "$ios_result"
printf 'macos_board=%s\n' "$root/docs/evidence/macos-board.png"
printf 'macos_live_server=%s\n' "$root/docs/evidence/macos-live-server.png"
printf 'ios_live_server=%s\n' "$root/docs/evidence/ios-live-server.png"
