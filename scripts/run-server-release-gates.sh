#!/bin/zsh
set -euo pipefail

if [[ "$(uname -s)" != 'Darwin' ]]; then
  echo 'server release gates require macOS' >&2
  exit 2
fi
export PATH="$HOME/.rustup/toolchains/1.99.1-aarch64-apple-darwin/bin:$HOME/.rustup/toolchains/stable-aarch64-apple-darwin/bin:$PATH"
: "${TEST_DATABASE_URL:?TEST_DATABASE_URL must point to a disposable PostgreSQL 18 maintenance database}"
: "${KSHIFT_PREVIOUS_SERVER_BUNDLE_ARCHIVE:?KSHIFT_PREVIOUS_SERVER_BUNDLE_ARCHIVE must point to the previous released server bundle}"
for command in cargo psql createdb dropdb pg_dump pg_restore openssl plutil launchctl jq python3 git node shasum; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "missing required command: $command" >&2
    exit 2
  }
done

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
version="${KSHIFT_VERSION:-0.1.0}"
channel="${KSHIFT_CHANNEL:-stable}"
source_commit="$(git rev-parse HEAD)"
if [[ "$channel" != 'stable' && "$channel" != 'hotfix' ]]; then
  echo 'server release gates require KSHIFT_CHANNEL=stable or hotfix' >&2
  exit 2
fi
if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
  echo 'server release gates require a clean source tree' >&2
  exit 2
fi

scratch="$(mktemp -d "${TMPDIR:-/tmp}/kshift-server-release-gates.XXXXXX")"
report="${KSHIFT_SERVER_RUNTIME_EVIDENCE_OUTPUT:-${TMPDIR:-/tmp}/kshift-server-runtime-evidence-$(date +%Y%m%dT%H%M%SZ).json}"
database_name="kshift_release_gate_$(openssl rand -hex 8)"

cleanup() {
  psql "$TEST_DATABASE_URL" \
    -v ON_ERROR_STOP=1 \
    -c "DROP DATABASE IF EXISTS \"$database_name\" WITH (FORCE)" \
    >/dev/null 2>&1 || true
  rm -rf "$scratch"
}
trap cleanup EXIT

mkdir -p "$(dirname "$report")" "$scratch/candidate" "$scratch/previous"
KSHIFT_VERSION="$version" \
KSHIFT_CHANNEL="$channel" \
KSHIFT_SOURCE_COMMIT="$source_commit" \
KSHIFT_OUTPUT_DIR="$scratch/dist" \
  ./release/platform/build-server.sh >/dev/null
candidate_archive="$(find "$scratch/dist" -maxdepth 1 -name 'kshift-*-server-macos-arm64.tar.gz' -print -quit)"
[[ -n "$candidate_archive" ]]
tar -xzf "$candidate_archive" -C "$scratch/candidate"
tar -xzf "$KSHIFT_PREVIOUS_SERVER_BUNDLE_ARCHIVE" -C "$scratch/previous"
mkdir -p "$scratch/candidate/etc" "$scratch/previous/etc"

jq -e --arg version "$version" --arg channel "$channel" --arg source "$source_commit" \
  '.version == $version and .channel == $channel and .source_commit == $source' \
  "$scratch/candidate/BUILD_INFO.json" >/dev/null
previous_version="$(jq -r '.version' "$scratch/previous/BUILD_INFO.json")"
previous_source_commit="$(jq -r '.source_commit' "$scratch/previous/BUILD_INFO.json")"
[[ "$previous_source_commit" =~ ^[0-9a-f]{40}$ ]]

psql "$TEST_DATABASE_URL" -v ON_ERROR_STOP=1 -c "CREATE DATABASE \"$database_name\"" >/dev/null
database_url="$(
  python3 - "$TEST_DATABASE_URL" "$database_name" <<'PY'
import sys
import urllib.parse
parts = urllib.parse.urlsplit(sys.argv[1])
print(urllib.parse.urlunsplit((parts.scheme, parts.netloc, '/' + sys.argv[2], parts.query, parts.fragment)))
PY
)"

env KSHIFT_DATABASE_URL="$database_url" \
  "$scratch/previous/bin/kshift-server" migrate > "$scratch/previous-migrate.json"
psql "$database_url" -v ON_ERROR_STOP=1 >/dev/null <<'SQL'
INSERT INTO kshift.app_user (id, display_name, is_admin)
VALUES ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Release Gate User', true);
INSERT INTO kshift.project (
  id, name, time_zone, current_revision, created_by, created_at, updated_at
)
VALUES (
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'Release Gate Project',
  'UTC',
  1,
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  now(),
  now()
);
SQL
before_project_count="$(psql "$database_url" -Atc 'SELECT count(*) FROM kshift.project')"
env KSHIFT_DATABASE_URL="$database_url" \
  "$scratch/candidate/bin/kshift-server" migrate > "$scratch/candidate-migrate.json"
env KSHIFT_DATABASE_URL="$database_url" \
  "$scratch/candidate/bin/kshift-server" check > "$scratch/candidate-check.json"
after_project_count="$(psql "$database_url" -Atc 'SELECT count(*) FROM kshift.project')"
[[ "$before_project_count" == '1' ]]
[[ "$after_project_count" == "$before_project_count" ]]

env KSHIFT_DATABASE_URL="$TEST_DATABASE_URL" \
  KSHIFT_SERVER_BIN="$scratch/candidate/bin/kshift-server" \
  ./scripts/recovery-test.sh > "$scratch/recovery.log"
grep -Fxq 'rollback=verified' "$scratch/recovery.log"
grep -Fxq 'restore=verified' "$scratch/recovery.log"
grep -Eq '^projects=[0-9]+$' "$scratch/recovery.log"
recovery_digest="$(awk -F= '/^migration_digest=/{print $2}' "$scratch/recovery.log")"
candidate_digest="$(jq -r '.migration_digest' "$scratch/candidate-check.json")"
[[ "$recovery_digest" == "$candidate_digest" ]]

env TEST_DATABASE_URL="$TEST_DATABASE_URL" \
  KSHIFT_SERVER_BUNDLE_ARCHIVE="$candidate_archive" \
  KSHIFT_SERVER_LAUNCHD_REPORT="$scratch/launchd.json" \
  ./scripts/test-server-launchd-restart.sh >/dev/null
[[ "$(jq -r '.status' "$scratch/launchd.json")" == 'passed' ]]
[[ "$(jq -r '.source_tree_state' "$scratch/launchd.json")" == 'clean' ]]
[[ "$(jq -r '.source_commit' "$scratch/launchd.json")" == "$source_commit" ]]

source_inputs="$(node release/tools/runtime-evidence.mjs source-digest --root "$root")"
source_inputs_sha256="$(jq -r '.sha256' <<<"$source_inputs")"
server_sha256="$(shasum -a 256 "$scratch/candidate/bin/kshift-server" | awk '{print $1}')"
ops_sha256="$(shasum -a 256 "$scratch/candidate/bin/kshift-ops" | awk '{print $1}')"
bundle_payload_sha256="$(
  node release/tools/runtime-evidence.mjs tree-digest \
    --root "$scratch/candidate" \
    --exclude BUILD_INFO.json | jq -r '.sha256'
)"
[[ "$server_sha256" == "$(jq -r '.server_sha256' "$scratch/launchd.json")" ]]
[[ "$ops_sha256" == "$(jq -r '.ops_sha256' "$scratch/launchd.json")" ]]
[[ "$bundle_payload_sha256" == "$(jq -r '.bundle_payload_sha256' "$scratch/launchd.json")" ]]

jq -n \
  --arg generated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg version "$version" \
  --arg channel "$channel" \
  --arg source_commit "$source_commit" \
  --arg source_inputs_sha256 "$source_inputs_sha256" \
  --arg server_sha256 "$server_sha256" \
  --arg ops_sha256 "$ops_sha256" \
  --arg bundle_payload_sha256 "$bundle_payload_sha256" \
  --arg os_version "$(sw_vers -productVersion)" \
  --arg hardware_model "$(sysctl -n hw.model)" \
  --arg previous_version "$previous_version" \
  --arg previous_source_commit "$previous_source_commit" \
  --slurpfile launchd "$scratch/launchd.json" \
  --slurpfile check "$scratch/candidate-check.json" \
  '{
    schema_version: "1",
    kind: "runtime-release-evidence",
    product: "Kshift",
    version: $version,
    channel: $channel,
    platform: "server",
    generated_at: $generated,
    source: {
      commit: $source_commit,
      tree_state: "clean",
      input_algorithm: "kshift-runtime-inputs-v1",
      input_sha256: $source_inputs_sha256
    },
    host: {
      os: "macOS",
      os_version: $os_version,
      architecture: "arm64",
      hardware_model: $hardware_model,
      postgresql_major: 18,
      postgresql_version: $check[0].postgres_version
    },
    artifact: {
      server_sha256: $server_sha256,
      ops_sha256: $ops_sha256,
      bundle_payload_sha256: $bundle_payload_sha256
    },
    gates: [
      {
        name: "health",
        status: "passed",
        detail: {
          before: $launchd[0].health_before_restart,
          after: $launchd[0].health_after_restart,
          transport: $launchd[0].transport
        }
      },
      {
        name: "migration",
        status: "passed",
        detail: {
          status: "passed",
          previous_version: $previous_version,
          previous_source_commit: $previous_source_commit,
          schema_version: ($check[0].schema_version | tostring),
          migration_digest: $check[0].migration_digest,
          migration_count: $check[0].migration_count,
          postgres_major: 18,
          postgres_version: $check[0].postgres_version,
          project_rows_preserved: true
        }
      },
      {
        name: "backup-restore",
        status: "passed",
        detail: {
          restore_verified: true,
          rollback_verified: true,
          project_count_match: true,
          migration_digest_match: true
        }
      },
      {
        name: "startup-recovery",
        status: "passed",
        detail: {
          supervisor: $launchd[0].supervisor,
          restart_signal: $launchd[0].restart_signal,
          runs: $launchd[0].runs,
          replayed_pre_restart_event: $launchd[0].verified.replayed_pre_restart_event,
          revision_advanced: ($launchd[0].verified.new_revision > $launchd[0].verified.snapshot_revision_before_restart)
        }
      },
      {
        name: "logs",
        status: "passed",
        detail: $launchd[0].logs
      }
    ],
    limitations: [
      "Runtime gates ran on the internal Apple-silicon macOS host with PostgreSQL 18.7.",
      "Server artifacts remain unsigned and are distributed as internal server bundles."
    ]
  }' > "$report"

node release/tools/runtime-evidence.mjs verify \
  --root "$root" \
  --evidence "$report" \
  --platform server \
  --version "$version" \
  --channel "$channel" \
  --candidate-commit "$source_commit" \
  --bundle "$scratch/candidate" \
  --expected-gates 'health,migration,backup-restore,startup-recovery,logs' \
  --output "$scratch/verified-gates.json" >/dev/null

printf 'server_runtime_evidence=%s\n' "$report"
