#!/bin/zsh
set -euo pipefail

port="${KSHIFT_TEST_DB_PORT:-55433}"
image="${KSHIFT_POSTGRES_IMAGE:-docker.m.daocloud.io/library/postgres:18}"
container="kshift-r3-pg-${port}-$$"

cleanup() {
  docker rm -f "$container" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

docker run -d --rm \
  --name "$container" \
  -e POSTGRES_PASSWORD=kshift_test \
  -e POSTGRES_DB=kshift_test \
  -p "${port}:5432" \
  "$image" >/dev/null

ready=0
for _ in {1..60}; do
  if docker exec "$container" psql -U postgres -d kshift_test -Atc 'SELECT 1' >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done

if [[ "$ready" != "1" ]]; then
  docker logs "$container"
  exit 1
fi

KSHIFT_TEST_DATABASE_URL="postgres://postgres:kshift_test@127.0.0.1:${port}/kshift_test" \
  cargo test -p kshift-plan-store
