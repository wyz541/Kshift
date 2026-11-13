#!/usr/bin/env bash
set -euo pipefail

: "${KSHIFT_DATABASE_URL:?KSHIFT_DATABASE_URL must point to a maintenance database}"

BASE_URL="${KSHIFT_DATABASE_URL%/*}"
SOURCE_DB="kshift_recovery_source_$$"
RESTORE_DB="kshift_recovery_restore_$$"
SOURCE_URL="${BASE_URL}/${SOURCE_DB}"
RESTORE_URL="${BASE_URL}/${RESTORE_DB}"
WORK_DIR="${TMPDIR:-/tmp}/kshift-recovery-$$"
BINARY="${KSHIFT_SERVER_BIN:-target/debug/kshift-server}"
DUMP_FILE="${WORK_DIR}/source.dump"

cleanup() {
  set +e
  dropdb --if-exists --maintenance-db="$KSHIFT_DATABASE_URL" "$SOURCE_DB" >/dev/null 2>&1
  dropdb --if-exists --maintenance-db="$KSHIFT_DATABASE_URL" "$RESTORE_DB" >/dev/null 2>&1
  rm -rf "$WORK_DIR"
}

trap cleanup EXIT
mkdir -p "$WORK_DIR"

if [[ ! -x "$BINARY" ]]; then
  echo "missing $BINARY; run cargo build -p kshift-server first" >&2
  exit 1
fi

createdb --maintenance-db="$KSHIFT_DATABASE_URL" "$SOURCE_DB"
KSHIFT_DATABASE_URL="$SOURCE_URL" "$BINARY" migrate >"${WORK_DIR}/migrate.json"

psql "$SOURCE_URL" -v ON_ERROR_STOP=1 >/dev/null <<'SQL'
INSERT INTO kshift.app_user (id, display_name, is_admin)
VALUES ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Recovery User', true);
INSERT INTO kshift.project (
  id, name, time_zone, current_revision, created_by, created_at, updated_at
)
VALUES (
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'Recovery Project',
  'UTC',
  1,
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  now(),
  now()
);
SQL

pg_dump --format=custom --no-owner --no-acl --file="$DUMP_FILE" "$SOURCE_URL"

set +e
psql "$SOURCE_URL" -v ON_ERROR_STOP=1 >"${WORK_DIR}/rollback.log" 2>&1 <<'SQL'
BEGIN;
CREATE TABLE kshift.rollback_probe (id integer PRIMARY KEY);
DO $$
BEGIN
  RAISE EXCEPTION 'intentional rollback probe';
END
$$;
COMMIT;
SQL
ROLLBACK_STATUS=$?
set -e

if [[ $ROLLBACK_STATUS -eq 0 ]]; then
  echo "intentional rollback probe unexpectedly succeeded" >&2
  exit 1
fi

PROBE_STATE=$(psql "$SOURCE_URL" -Atc "SELECT to_regclass('kshift.rollback_probe') IS NULL")
if [[ "$PROBE_STATE" != "t" ]]; then
  echo "failed transaction left a partial table" >&2
  exit 1
fi

createdb --maintenance-db="$KSHIFT_DATABASE_URL" "$RESTORE_DB"
pg_restore --no-owner --no-acl --dbname="$RESTORE_URL" "$DUMP_FILE"
KSHIFT_DATABASE_URL="$RESTORE_URL" "$BINARY" check >"${WORK_DIR}/check-restored.json"

SOURCE_PROJECTS=$(psql "$SOURCE_URL" -Atc "SELECT count(*) FROM kshift.project")
RESTORE_PROJECTS=$(psql "$RESTORE_URL" -Atc "SELECT count(*) FROM kshift.project")
SOURCE_DIGEST=$(psql "$SOURCE_URL" -Atc "SELECT migration_digest FROM kshift.schema_metadata WHERE id = 1")
RESTORE_DIGEST=$(psql "$RESTORE_URL" -Atc "SELECT migration_digest FROM kshift.schema_metadata WHERE id = 1")

if [[ "$SOURCE_PROJECTS" != "$RESTORE_PROJECTS" ]]; then
  echo "project count mismatch after restore" >&2
  exit 1
fi
if [[ "$SOURCE_DIGEST" != "$RESTORE_DIGEST" ]]; then
  echo "migration digest mismatch after restore" >&2
  exit 1
fi

printf 'rollback=verified\nrestore=verified\nprojects=%s\nmigration_digest=%s\n' \
  "$RESTORE_PROJECTS" "$RESTORE_DIGEST"
