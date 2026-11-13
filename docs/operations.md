---
slug: /docs/r1-operations
title: Kshift R1 operations
type: reference
status: review
updated: "2026-11-13"
keywords:
  - PostgreSQL 18
  - TLS
  - migration
  - recovery
  - health check
description: 描述 Kshift R1 server 的角色、TLS、迁移、恢复和健康检查操作。
---

# Kshift R1 operations

## PostgreSQL roles

Use separate roles.

| Role | Permission |
| --- | --- |
| `kshift_owner` | owns schema and runs migrations |
| `kshift_app` | runtime DML only |
| `kshift_backup` | backup reads only |

Do not run the application as a superuser.

Example grants after migration:

```sql
GRANT USAGE ON SCHEMA kshift TO kshift_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA kshift TO kshift_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA kshift TO kshift_app;
ALTER DEFAULT PRIVILEGES FOR ROLE kshift_owner IN SCHEMA kshift
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO kshift_app;
ALTER DEFAULT PRIVILEGES FOR ROLE kshift_owner IN SCHEMA kshift
  GRANT USAGE, SELECT ON SEQUENCES TO kshift_app;
GRANT USAGE ON SCHEMA kshift TO kshift_backup;
GRANT SELECT ON ALL TABLES IN SCHEMA kshift TO kshift_backup;
```

Use `\password kshift_app` in `psql`. Do not put passwords in shell history,
source files, logs or Release assets.

## TLS

Set both paths.

```sh
export KSHIFT_TLS_CERT_PATH='/absolute/path/server.crt'
export KSHIFT_TLS_KEY_PATH='/absolute/path/server.key'
```

The certificate SAN must include the internal DNS name and loopback name used
by clients. Stable environments must not set `KSHIFT_ALLOW_INSECURE=true`.

## Migration

1. Create a `pg_dump --format=custom --no-owner --no-acl` backup.
2. Record PostgreSQL version, source commit, schema version and dump SHA-256.
3. Run `kshift-server migrate`.
4. Keep the printed migration digest.
5. Run `kshift-server check`.
6. Start or restart the server.

The server does not apply migrations at startup. It verifies PostgreSQL major
version 18, successful migration count, schema version and migration digest.
A mismatch stops startup.

## Recovery

Use the reviewed backup when a migration must be reversed.

1. Create an empty temporary database.
2. Run `pg_restore --no-owner --no-acl`.
3. Run `kshift-server check` against the restored database.
4. Run schema, foreign key and business invariant checks.
5. Switch the server DSN only after checks pass.
6. Keep the failed database until the incident review finishes.

Run `scripts/recovery-test.sh` for the repeatable rollback and restore drill.

## Health

Use the standard gRPC health service.

- Service name `""` reports overall readiness.
- Service name `kshift.v1.KshiftService` reports server readiness.
- A database ping failure changes both to `NOT_SERVING`.
- A recovery changes both back to `SERVING`.

Do not use reflection. Stable environments disable reflection.

## Shutdown

Send `SIGTERM` or `SIGINT`.

The server stops accepting new requests, waits for active requests, cancels
background tasks, closes the PostgreSQL pool and exits. Client streams close;
clients reconnect with jittered exponential backoff.

## Logs

Logs are JSON on stdout.

Sensitive values are forbidden in logs:

- bearer token
- database URL and password
- full command body
- attachment bytes

Log fields include request ID, user ID, project ID, client ID, command ID,
revision and command name.

## Retention

The cleanup task runs hourly.

- Outbox events expire after 7 days by default.
- Idempotency results expire after 7 days.
- A client with an older cursor receives `ResetRequired`.
