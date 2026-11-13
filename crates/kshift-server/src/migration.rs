use anyhow::{bail, Context};
use chrono::{DateTime, Utc};
use sqlx::PgPool;

use crate::db;

pub static MIGRATOR: sqlx::migrate::Migrator = sqlx::migrate!("../../migrations");

pub const MIGRATION_DIGEST: &str = env!("KSHIFT_MIGRATION_DIGEST");
const MIGRATION_COUNT_TEXT: &str = env!("KSHIFT_MIGRATION_COUNT");

#[derive(Clone, Debug, serde::Serialize)]
pub struct MigrationEvidence {
    pub schema_version: u32,
    pub migration_digest: String,
    pub migration_count: i64,
    pub postgres_version: String,
    pub postgres_version_num: i32,
    pub applied_at: Option<DateTime<Utc>>,
}

pub async fn run(pool: &PgPool) -> anyhow::Result<MigrationEvidence> {
    let database = db::require_postgres_18(pool).await?;
    MIGRATOR
        .run(pool)
        .await
        .context("failed to apply Kshift migrations")?;

    let expected_count = expected_migration_count()?;
    let applied_count = successful_migration_count(pool).await?;
    if applied_count != expected_count {
        bail!("migration count mismatch: expected {expected_count}, database has {applied_count}");
    }

    sqlx::query(
        r#"
        INSERT INTO kshift.schema_metadata (
            id, schema_version, migration_digest, applied_at, postgres_version
        )
        VALUES (1, $1, $2, now(), $3)
        ON CONFLICT (id) DO UPDATE SET
            schema_version = EXCLUDED.schema_version,
            migration_digest = EXCLUDED.migration_digest,
            applied_at = EXCLUDED.applied_at,
            postgres_version = EXCLUDED.postgres_version
        "#,
    )
    .bind(domain::SCHEMA_VERSION as i32)
    .bind(MIGRATION_DIGEST)
    .bind(&database.server_version)
    .execute(pool)
    .await
    .context("failed to update schema metadata")?;

    verify(pool).await?;
    let applied_at = sqlx::query_scalar::<_, DateTime<Utc>>(
        "SELECT applied_at FROM kshift.schema_metadata WHERE id = 1",
    )
    .fetch_one(pool)
    .await
    .context("failed to read schema metadata")?;

    Ok(MigrationEvidence {
        schema_version: domain::SCHEMA_VERSION,
        migration_digest: MIGRATION_DIGEST.to_owned(),
        migration_count: expected_count,
        postgres_version: database.server_version,
        postgres_version_num: database.server_version_num,
        applied_at: Some(applied_at),
    })
}

pub async fn verify(pool: &PgPool) -> anyhow::Result<MigrationEvidence> {
    let database = db::require_postgres_18(pool).await?;
    let expected_count = expected_migration_count()?;
    let applied_count = successful_migration_count(pool).await?;
    if applied_count != expected_count {
        bail!(
            "schema is not ready: expected {expected_count} successful migrations, database has {applied_count}"
        );
    }

    let failed_count =
        sqlx::query_scalar::<_, i64>("SELECT count(*) FROM _sqlx_migrations WHERE success = false")
            .fetch_one(pool)
            .await
            .context("failed to inspect migration failures")?;
    if failed_count != 0 {
        bail!("schema is not ready: database contains failed migrations");
    }

    verify_migration_checksums(pool).await?;

    let metadata = sqlx::query_as::<_, SchemaMetadata>(
        r#"
        SELECT schema_version, migration_digest, applied_at, postgres_version
        FROM kshift.schema_metadata
        WHERE id = 1
        "#,
    )
    .fetch_optional(pool)
    .await
    .context("failed to read migration metadata; run kshift-server migrate")?
    .context("schema metadata is missing; run kshift-server migrate")?;

    if metadata.schema_version != domain::SCHEMA_VERSION as i32 {
        bail!(
            "schema version mismatch: expected {}, database has {}",
            domain::SCHEMA_VERSION,
            metadata.schema_version
        );
    }
    if metadata.migration_digest != MIGRATION_DIGEST {
        bail!("migration digest mismatch; run a reviewed migration or restore a matching backup");
    }

    Ok(MigrationEvidence {
        schema_version: domain::SCHEMA_VERSION,
        migration_digest: metadata.migration_digest,
        migration_count: applied_count,
        postgres_version: database.server_version,
        postgres_version_num: database.server_version_num,
        applied_at: Some(metadata.applied_at),
    })
}

async fn verify_migration_checksums(pool: &PgPool) -> anyhow::Result<()> {
    let applied = sqlx::query_as::<_, AppliedMigrationRow>(
        "SELECT version, checksum FROM _sqlx_migrations WHERE success = true ORDER BY version",
    )
    .fetch_all(pool)
    .await
    .context("failed to inspect migration checksums")?;
    let expected: Vec<_> = MIGRATOR.iter().collect();

    if applied.len() != expected.len() {
        bail!(
            "migration source mismatch: expected {} migrations, database has {}",
            expected.len(),
            applied.len()
        );
    }

    for (applied, expected) in applied.iter().zip(expected) {
        if applied.version != expected.version
            || applied.checksum.as_slice() != expected.checksum.as_ref()
        {
            bail!(
                "migration checksum mismatch at version {}; restore a matching backup",
                expected.version
            );
        }
    }
    Ok(())
}

async fn successful_migration_count(pool: &PgPool) -> anyhow::Result<i64> {
    sqlx::query_scalar::<_, i64>("SELECT count(*) FROM _sqlx_migrations WHERE success = true")
        .fetch_one(pool)
        .await
        .context("failed to inspect applied migrations")
}

fn expected_migration_count() -> anyhow::Result<i64> {
    MIGRATION_COUNT_TEXT
        .parse()
        .context("embedded migration count is invalid")
}

#[derive(sqlx::FromRow)]
struct AppliedMigrationRow {
    version: i64,
    checksum: Vec<u8>,
}

#[derive(sqlx::FromRow)]
struct SchemaMetadata {
    schema_version: i32,
    migration_digest: String,
    applied_at: DateTime<Utc>,
    #[allow(dead_code)]
    postgres_version: String,
}
