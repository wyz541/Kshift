# Kshift migrations

SQLx applies these migrations in filename order.

Rules:

1. Do not edit an applied migration.
2. Add a new migration for every schema change.
3. Update `SCHEMA_VERSION` when the wire or persistence schema changes.
4. Run a backup before a production migration.
5. Run `kshift-server migrate` and keep the migration digest output.
6. Run `kshift-server check` after the migration.

The server refuses to start unless PostgreSQL major version 18 and the
database migration digest match the embedded migrations.

## R3 migration

`0002_plan_depth.sql` adds R3 snapshot, immutable history state and attachment
content tables. Current schema version is `3` and migration count is `2`.
