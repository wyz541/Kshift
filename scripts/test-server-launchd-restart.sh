#!/bin/zsh
set -euo pipefail

if [[ "$(uname -s)" != 'Darwin' ]]; then
  echo 'server launchd restart test requires macOS' >&2
  exit 2
fi
export PATH="$HOME/.rustup/toolchains/stable-aarch64-apple-darwin/bin:$PATH"
: "${TEST_DATABASE_URL:?TEST_DATABASE_URL must point to a disposable PostgreSQL 18 maintenance database}"
for command in cargo psql openssl plutil launchctl jq python3 git; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "missing required command: $command" >&2
    exit 2
  }
done

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
uid="$(id -u)"
label="com.wyz541.kshift.server-test.$$"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/kshift-server-launchd.XXXXXX")"
report="${KSHIFT_SERVER_LAUNCHD_REPORT:-${TMPDIR:-/tmp}/kshift-server-launchd-report-$(date +%Y%m%dT%H%M%SZ).json}"
database_name="kshift_launchd_$(openssl rand -hex 8)"
bundle="$scratch/bundle"
project_id="$(uuidgen | tr '[:upper:]' '[:lower:]')"
user_id="$(uuidgen | tr '[:upper:]' '[:lower:]')"
token="$(openssl rand -hex 32)"
source_commit="$(git rev-parse HEAD)"
source_tree_state='clean'
if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
  source_tree_state='dirty'
fi

cleanup() {
  launchctl bootout "gui/$uid/$label" >/dev/null 2>&1 || true
  psql "$TEST_DATABASE_URL" \
    -v ON_ERROR_STOP=1 \
    -c "DROP DATABASE IF EXISTS \"$database_name\" WITH (FORCE)" \
    >/dev/null 2>&1 || true
  rm -rf "$scratch"
}
trap cleanup EXIT

mkdir -p "$(dirname "$report")" "$bundle"
psql "$TEST_DATABASE_URL" -v ON_ERROR_STOP=1 -c "CREATE DATABASE \"$database_name\"" >/dev/null
database_url="$(
  python3 - "$TEST_DATABASE_URL" "$database_name" <<'PY'
import sys
import urllib.parse
parts = urllib.parse.urlsplit(sys.argv[1])
print(urllib.parse.urlunsplit((parts.scheme, parts.netloc, '/' + sys.argv[2], parts.query, parts.fragment)))
PY
)"

KSHIFT_VERSION='0.1.0' \
KSHIFT_CHANNEL='preview' \
KSHIFT_SOURCE_COMMIT="$source_commit" \
KSHIFT_OUTPUT_DIR="$scratch/dist" \
  "$root/release/platform/build-server.sh" >/dev/null
archive="$(
  find "$scratch/dist" -maxdepth 1 -name 'kshift-*-server-macos-arm64.tar.gz' -print | head -n 1
)"
[[ -n "$archive" ]]
tar -xzf "$archive" -C "$bundle"
mkdir -p "$bundle/etc"

env KSHIFT_DATABASE_URL="$database_url" \
  "$bundle/bin/kshift-server" migrate > "$scratch/migration.json"
printf '{"id":"%s","display_name":"Launchd Probe","is_admin":true}\n' "$user_id" |
  env KSHIFT_DATABASE_URL="$database_url" \
    "$bundle/bin/kshift-server" bootstrap-user > "$scratch/bootstrap-user.json"
token_hash="$(
  printf '%s' "$token" |
    env KSHIFT_DATABASE_URL="$database_url" \
      "$bundle/bin/kshift-server" hash-token
)"
auth_file="$bundle/etc/auth.json"
cat > "$auth_file" <<JSON
{"tokens":[{"sha256":"$token_hash","user_id":"$user_id"}]}
JSON
chmod 600 "$auth_file"

tls_dir="$scratch/tls"
mkdir -p "$tls_dir"
openssl req -x509 -newkey rsa:2048 -sha256 -days 2 -nodes \
  -subj '/CN=Kshift Test CA' \
  -addext 'basicConstraints=critical,CA:TRUE' \
  -addext 'keyUsage=critical,keyCertSign,cRLSign' \
  -keyout "$tls_dir/ca-key.pem" \
  -out "$tls_dir/ca.pem" >/dev/null 2>&1
openssl req -new -newkey rsa:2048 -sha256 -nodes \
  -subj '/CN=localhost' \
  -keyout "$tls_dir/server-key.pem" \
  -out "$tls_dir/server.csr" >/dev/null 2>&1
cat > "$tls_dir/server.ext" <<'EXT'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:localhost,IP:127.0.0.1
EXT
openssl x509 -req -sha256 -days 2 \
  -in "$tls_dir/server.csr" \
  -CA "$tls_dir/ca.pem" \
  -CAkey "$tls_dir/ca-key.pem" \
  -CAcreateserial \
  -extfile "$tls_dir/server.ext" \
  -out "$tls_dir/server.pem" >/dev/null 2>&1

port="$(
  python3 - <<'PY'
import socket
sock = socket.socket()
sock.bind(('127.0.0.1', 0))
print(sock.getsockname()[1])
sock.close()
PY
)"
endpoint="https://localhost:$port"
env_file="$bundle/etc/kshift.env"
python3 - "$env_file" "$database_url" "$auth_file" "$tls_dir/server.pem" "$tls_dir/server-key.pem" "$port" <<'PY'
import shlex
import sys
from pathlib import Path
path = Path(sys.argv[1])
values = {
    'KSHIFT_DATABASE_URL': sys.argv[2],
    'KSHIFT_AUTH_FILE': sys.argv[3],
    'KSHIFT_TLS_CERT_PATH': sys.argv[4],
    'KSHIFT_TLS_KEY_PATH': sys.argv[5],
    'KSHIFT_BIND_ADDR': f'127.0.0.1:{sys.argv[6]}',
    'KSHIFT_DB_MIN_CONNECTIONS': '1',
    'KSHIFT_DB_MAX_CONNECTIONS': '20',
    'KSHIFT_LOG_FILTER': 'kshift_server=info',
}
path.write_text(''.join(f'export {key}={shlex.quote(value)}\n' for key, value in values.items()))
PY
chmod 600 "$env_file"

log_dir="$scratch/logs"
mkdir -p "$log_dir"
plist="$scratch/$label.plist"
python3 - "$plist" "$label" "$bundle" "$env_file" "$log_dir" <<'PY'
import plistlib
import sys
from pathlib import Path
path, label, bundle, env_file, log_dir = sys.argv[1:]
payload = {
    'Label': label,
    'ProgramArguments': [f'{bundle}/bin/kshift-server-run'],
    'EnvironmentVariables': {'KSHIFT_ENV_FILE': env_file},
    'RunAtLoad': True,
    'KeepAlive': {'SuccessfulExit': False},
    'ThrottleInterval': 1,
    'ProcessType': 'Background',
    'StandardOutPath': f'{log_dir}/server.log',
    'StandardErrorPath': f'{log_dir}/server.error.log',
}
with Path(path).open('wb') as handle:
    plistlib.dump(payload, handle)
PY
plutil -lint "$plist" >/dev/null

cargo build --locked -p kshift-client --example launchd_probe
probe="$root/target/debug/examples/launchd_probe"

run_probe() {
  local mode="$1"
  local output="$2"
  env \
    KSHIFT_ENDPOINT="$endpoint" \
    KSHIFT_CA_PATH="$tls_dir/ca.pem" \
    KSHIFT_TLS_DOMAIN='localhost' \
    KSHIFT_TOKEN="$token" \
    KSHIFT_PROJECT_ID="$project_id" \
    KSHIFT_PROBE_OUTPUT="$output" \
    "$probe" "$mode"
}

read_pid() {
  launchctl print "gui/$uid/$label" 2>/dev/null |
    awk '/^[[:space:]]*pid = /{print $3; exit}'
}

read_runs() {
  launchctl print "gui/$uid/$label" 2>/dev/null |
    awk '/^[[:space:]]*runs = /{print $3; exit}'
}

launchctl bootstrap "gui/$uid" "$plist"
old_pid=''
for _ in {1..100}; do
  old_pid="$(read_pid)"
  [[ -n "$old_pid" ]] && break
  sleep 0.2
done
[[ -n "$old_pid" ]]
run_probe health "$scratch/health-before.json"
run_probe prepare "$scratch/prepare.json"

kill -KILL "$old_pid"
new_pid=''
for _ in {1..150}; do
  candidate="$(read_pid)"
  if [[ -n "$candidate" && "$candidate" != "$old_pid" ]]; then
    new_pid="$candidate"
    break
  fi
  sleep 0.2
done
[[ -n "$new_pid" ]]
run_probe verify "$scratch/verify.json"

runs="$(read_runs)"
[[ -n "$runs" ]]
[[ "$runs" -ge 2 ]]
jq -n \
  --arg label "$label" \
  --arg source_commit "$source_commit" \
  --arg source_tree_state "$source_tree_state" \
  --arg old_pid "$old_pid" \
  --arg new_pid "$new_pid" \
  --argjson runs "$runs" \
  --slurpfile health "$scratch/health-before.json" \
  --slurpfile prepared "$scratch/prepare.json" \
  --slurpfile verified "$scratch/verify.json" \
  '{
    status: "passed",
    supervisor: "LaunchAgent",
    transport: "tls",
    server_bundle: "release",
    source_commit: $source_commit,
    source_tree_state: $source_tree_state,
    label: $label,
    restart_signal: "SIGKILL",
    runs: $runs,
    old_pid: $old_pid,
    new_pid: $new_pid,
    health_before_restart: $health[0].health,
    health_after_restart: $verified[0].health,
    prepared: $prepared[0],
    verified: $verified[0]
  }' > "$report"

printf 'server_launchd_report=%s\n' "$report"
