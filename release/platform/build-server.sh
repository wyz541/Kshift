#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
version="${KSHIFT_VERSION:?KSHIFT_VERSION is required}"
channel="${KSHIFT_CHANNEL:-preview}"
source_commit="${KSHIFT_SOURCE_COMMIT:?KSHIFT_SOURCE_COMMIT is required}"
if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo 'version must be SemVer core MAJOR.MINOR.PATCH' >&2
  exit 2
fi
output_dir="${KSHIFT_OUTPUT_DIR:-$root/dist}"
target="${KSHIFT_TARGET_TRIPLE:-aarch64-apple-darwin}"

if [[ ! -f "$root/Cargo.toml" ]]; then
  echo 'Cargo.toml is missing; server release cannot be built' >&2
  exit 2
fi
if [[ ! "$source_commit" =~ ^[0-9a-f]{40}$ ]]; then
  echo 'KSHIFT_SOURCE_COMMIT must be 40 lowercase hexadecimal characters' >&2
  exit 2
fi
if [[ "$channel" != 'stable' && "$channel" != 'preview' ]]; then
  echo 'KSHIFT_CHANNEL must be stable or preview' >&2
  exit 2
fi

cd "$root"
cargo build --locked --release --target "$target" -p kshift-server
mkdir -p "$output_dir"
staging="$(mktemp -d "$TMPDIR/kshift-server-bundle.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
install -d "$staging/bin" "$staging/sql" "$staging/launchd" "$staging/newsyslog" "$staging/deploy" "$staging/migrations"
install -m 0755 "$root/target/$target/release/kshift-server" "$staging/bin/kshift-server"
install -m 0755 "$root/ops/bin/kshift-ops" "$staging/bin/kshift-ops"
cat > "$staging/bin/kshift-server-run" <<'RUNNER'
#!/bin/zsh
set -euo pipefail
home="$(cd "$(dirname "$0")/.." && pwd)"
env_file="${KSHIFT_ENV_FILE:-$home/etc/kshift.env}"
if [[ -r "$env_file" ]]; then
  set -a
  source "$env_file"
  set +a
fi
exec "$home/bin/kshift-server"
RUNNER
chmod 0755 "$staging/bin/kshift-server-run"
cat > "$staging/bin/kshift-ops-run" <<'RUNNER'
#!/bin/zsh
set -euo pipefail
home="$(cd "$(dirname "$0")/.." && pwd)"
env_file="${KSHIFT_ENV_FILE:-$home/etc/kshift.env}"
if [[ -r "$env_file" ]]; then
  set -a
  source "$env_file"
  set +a
fi
exec "$home/bin/kshift-ops" "$@"
RUNNER
chmod 0755 "$staging/bin/kshift-ops-run"
ditto "$root/ops/kshift_ops" "$staging/kshift_ops"
ditto "$root/ops/sql" "$staging/sql"
ditto "$root/migrations" "$staging/migrations"
ditto "$root/ops/launchd" "$staging/launchd"
ditto "$root/ops/newsyslog" "$staging/newsyslog"
ditto "$root/deploy" "$staging/deploy"
if [[ -f "$root/scripts/recovery-test.sh" ]]; then
  install -m 0755 "$root/scripts/recovery-test.sh" "$staging/migrations/recovery-test.sh"
fi
cat > "$staging/BUILD_INFO.json" <<JSON
{
  "product": "Kshift",
  "version": "$version",
  "channel": "$channel",
  "source_commit": "$source_commit",
  "postgresql_major": 18,
  "target": "$target",
  "built_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
archive="$output_dir/kshift-$version-server-macos-arm64.tar.gz"
tar -C "$staging" -czf "$archive" .
shasum -a 256 "$archive" > "$archive.sha256"
printf '%s\n' "$archive"
