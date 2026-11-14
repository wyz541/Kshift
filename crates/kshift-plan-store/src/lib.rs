//! PostgreSQL persistence for the R3 plan-depth snapshot.

use chrono::NaiveDate;
use kshift_core::{
    PlanCommand, PlanCommandEnvelope, PlanCommandResponse, PlanDepthSnapshot, PlanDepthStore,
    PlanError, ReportRange, WorkReport,
};
use sqlx::{PgPool, Postgres, Transaction};
use thiserror::Error;
use uuid::Uuid;

#[derive(Debug, Error)]
pub enum PlanStoreError {
    #[error(transparent)]
    Database(#[from] sqlx::Error),
    #[error(transparent)]
    Serialization(#[from] serde_json::Error),
    #[error(transparent)]
    Domain(#[from] PlanError),
    #[error("project snapshot was not initialized")]
    NotInitialized,
    #[error("project identifier is not a UUID")]
    InvalidProjectIdentifier,
    #[error("actor identifier is not a UUID")]
    InvalidActorIdentifier,
}

pub struct PlanSnapshotStore {
    pool: PgPool,
}

impl PlanSnapshotStore {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    pub async fn migrate(&self) -> anyhow::Result<()> {
        sqlx::migrate!("../../migrations").run(&self.pool).await?;
        Ok(())
    }

    pub async fn initialize(
        &self,
        snapshot: &PlanDepthSnapshot,
        actor_id: Uuid,
    ) -> Result<(), PlanStoreError> {
        let mut tx = self.pool.begin().await?;
        let project_id = project_uuid(&snapshot.project.id)?;
        sqlx::query(
            "INSERT INTO kshift.plan_snapshot (project_id, revision, payload)
             VALUES ($1, $2, $3)
             ON CONFLICT (project_id) DO NOTHING",
        )
        .bind(project_id)
        .bind(i64::try_from(snapshot.project.revision).unwrap_or_default())
        .bind(sqlx::types::Json(snapshot))
        .execute(&mut *tx)
        .await?;
        if !actor_id.is_nil() {
            upsert_state(
                &mut tx,
                snapshot,
                actor_id,
                "seeded",
                "初始化计划深度快照",
                None,
                &snapshot.content_sha256(),
            )
            .await?;
        }
        sqlx::query(
            "UPDATE kshift.project SET current_revision = $2, updated_at = now()
             WHERE id = $1",
        )
        .bind(project_id)
        .bind(i64::try_from(snapshot.project.revision).unwrap_or_default())
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        Ok(())
    }

    pub async fn load(&self, project_id: Uuid) -> Result<PlanDepthStore, PlanStoreError> {
        let current: Option<(sqlx::types::Json<PlanDepthSnapshot>,)> =
            sqlx::query_as("SELECT payload FROM kshift.plan_snapshot WHERE project_id = $1")
                .bind(project_id)
                .fetch_optional(&self.pool)
                .await?;
        let (current,) = current.ok_or(PlanStoreError::NotInitialized)?;
        let states: Vec<(sqlx::types::Json<PlanDepthSnapshot>,)> = sqlx::query_as(
            "SELECT payload FROM kshift.plan_state
             WHERE project_id = $1 AND revision <> $2
             ORDER BY revision ASC",
        )
        .bind(project_id)
        .bind(i64::try_from(current.0.project.revision).unwrap_or_default())
        .fetch_all(&self.pool)
        .await?;
        Ok(PlanDepthStore::with_history(
            current.0,
            states.into_iter().map(|(state,)| state.0).collect(),
        )?)
    }

    pub async fn execute(
        &self,
        envelope: PlanCommandEnvelope,
    ) -> Result<PlanCommandResponse, PlanStoreError> {
        if let Some(snapshot) = self
            .idempotent_response(envelope.project_id, &envelope.request_id)
            .await?
        {
            return Ok(PlanCommandResponse {
                ok: true,
                request_id: envelope.request_id,
                snapshot,
                affected_task_ids: affected_task_ids(&envelope.command),
                error: None,
            });
        }
        let store = self.load(envelope.project_id).await?;
        let before = store.snapshot().clone();
        let mut store = store;
        let response = store.execute(&envelope);
        if !response.ok {
            return Ok(response);
        }
        let after = response.snapshot.clone();
        let actor_id = envelope
            .actor_id
            .parse()
            .map_err(|_| PlanStoreError::InvalidActorIdentifier)?;
        let mut tx = self.pool.begin().await?;
        if let Err(error) = persist_execution(
            &mut tx, &store, &before, &after, &envelope, &response, actor_id,
        )
        .await
        {
            tx.rollback().await?;
            if let Some(conflict) = recover_conflict(&self.pool, envelope.project_id).await? {
                return Ok(PlanCommandResponse {
                    ok: false,
                    request_id: envelope.request_id,
                    snapshot: conflict.0,
                    affected_task_ids: Vec::new(),
                    error: Some(PlanError {
                        code: "revision_conflict".to_owned(),
                        message: "项目已被其他成员更新。请刷新后重试。".to_owned(),
                        current_revision: Some(conflict.1),
                        current_task_version: None,
                        task_id: None,
                    }),
                });
            }
            return Err(error);
        }
        tx.commit().await?;
        Ok(response)
    }

    pub async fn report(
        &self,
        project_id: Uuid,
        range: &ReportRange,
        today: NaiveDate,
    ) -> Result<WorkReport, PlanStoreError> {
        let store = self.load(project_id).await?;
        Ok(store.report(range, today)?)
    }

    pub async fn attachment(
        &self,
        project_id: Uuid,
        sha256: &str,
    ) -> Result<Option<Vec<u8>>, PlanStoreError> {
        let row: Option<(Vec<u8>,)> = sqlx::query_as(
            "SELECT content FROM kshift.plan_attachment
             WHERE project_id = $1 AND sha256 = $2",
        )
        .bind(project_id)
        .bind(sha256)
        .fetch_optional(&self.pool)
        .await?;
        Ok(row.map(|(content,)| content))
    }

    async fn idempotent_response(
        &self,
        project_id: Uuid,
        request_id: &str,
    ) -> Result<Option<PlanDepthSnapshot>, PlanStoreError> {
        let row: Option<(sqlx::types::Json<PlanDepthSnapshot>,)> = sqlx::query_as(
            "SELECT payload FROM kshift.plan_state
             WHERE project_id = $1 AND payload->'history'->0->>'id' = $2
             ORDER BY revision DESC
             LIMIT 1",
        )
        .bind(project_id)
        .bind(request_id)
        .fetch_optional(&self.pool)
        .await?;
        Ok(row.map(|(snapshot,)| snapshot.0))
    }
}

fn affected_task_ids(command: &PlanCommand) -> Vec<String> {
    match command {
        PlanCommand::CreateTask { task_id, .. }
        | PlanCommand::UpdateTask { task_id, .. }
        | PlanCommand::DeleteTask { task_id, .. }
        | PlanCommand::SetParent { task_id, .. }
        | PlanCommand::ReplaceDependencies { task_id, .. }
        | PlanCommand::SetTaskStatus { task_id, .. }
        | PlanCommand::AttachFile { task_id, .. } => vec![task_id.clone()],
        PlanCommand::Rollback { .. } => Vec::new(),
    }
}

async fn persist_execution(
    tx: &mut Transaction<'_, Postgres>,
    store: &PlanDepthStore,
    before: &PlanDepthSnapshot,
    after: &PlanDepthSnapshot,
    envelope: &PlanCommandEnvelope,
    response: &PlanCommandResponse,
    actor_id: Uuid,
) -> Result<(), PlanStoreError> {
    let project_id = project_uuid(&after.project.id)?;
    let expected = i64::try_from(envelope.expected_revision).unwrap_or_default();
    let revision = i64::try_from(after.project.revision).unwrap_or_default();
    let update = sqlx::query(
        "UPDATE kshift.plan_snapshot
         SET revision = $3, payload = $4, updated_at = now()
         WHERE project_id = $1 AND revision = $2",
    )
    .bind(project_id)
    .bind(expected)
    .bind(revision)
    .bind(sqlx::types::Json(after))
    .execute(&mut **tx)
    .await?;
    if update.rows_affected() != 1 {
        return Err(PlanStoreError::Database(sqlx::Error::RowNotFound));
    }

    for sha256 in store.retained_attachment_sha256() {
        let Some(content) = store.attachment_bytes(sha256) else {
            continue;
        };
        let Some(attachment) = after.attachments.iter().find(|item| item.sha256 == sha256) else {
            continue;
        };
        sqlx::query(
            "INSERT INTO kshift.plan_attachment (
                project_id, sha256, media_type, byte_size, filename, content
             ) VALUES ($1, $2, $3, $4, $5, $6)
             ON CONFLICT (project_id, sha256) DO NOTHING",
        )
        .bind(project_id)
        .bind(sha256)
        .bind(&attachment.media_type)
        .bind(i64::try_from(attachment.byte_size).unwrap_or_default())
        .bind(&attachment.filename)
        .bind(content)
        .execute(&mut **tx)
        .await?;
    }

    let history = response
        .snapshot
        .history
        .first()
        .ok_or(PlanStoreError::NotInitialized)?;
    upsert_state(
        tx,
        before,
        actor_id,
        "before",
        &envelope.request_id,
        None,
        &before.content_sha256(),
    )
    .await?;
    upsert_state(
        tx,
        after,
        actor_id,
        &history.action,
        &history.summary,
        history.restored_from_revision,
        &history.content_sha256,
    )
    .await?;
    sqlx::query(
        "UPDATE kshift.project SET current_revision = $2, updated_at = now()
         WHERE id = $1",
    )
    .bind(project_id)
    .bind(revision)
    .execute(&mut **tx)
    .await?;
    Ok(())
}

fn project_uuid(value: &str) -> Result<Uuid, PlanStoreError> {
    value
        .parse()
        .map_err(|_| PlanStoreError::InvalidProjectIdentifier)
}

async fn upsert_state(
    tx: &mut Transaction<'_, Postgres>,
    snapshot: &PlanDepthSnapshot,
    actor_id: Uuid,
    action: &str,
    summary: &str,
    restored_from_revision: Option<u64>,
    content_sha256: &str,
) -> Result<(), PlanStoreError> {
    sqlx::query(
        "INSERT INTO kshift.plan_state (
            project_id, revision, payload, actor_id, action, summary,
            restored_from_revision, content_sha256
         ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
         ON CONFLICT (project_id, revision) DO NOTHING",
    )
    .bind(project_uuid(&snapshot.project.id)?)
    .bind(i64::try_from(snapshot.project.revision).unwrap_or_default())
    .bind(sqlx::types::Json(snapshot))
    .bind(actor_id)
    .bind(action)
    .bind(summary)
    .bind(restored_from_revision.map(|value| value as i64))
    .bind(content_sha256)
    .execute(&mut **tx)
    .await?;
    Ok(())
}

async fn recover_conflict(
    pool: &PgPool,
    project_id: Uuid,
) -> Result<Option<(PlanDepthSnapshot, u64)>, PlanStoreError> {
    let row: Option<(sqlx::types::Json<PlanDepthSnapshot>, i64)> =
        sqlx::query_as("SELECT payload, revision FROM kshift.plan_snapshot WHERE project_id = $1")
            .bind(project_id)
            .fetch_optional(pool)
            .await?;
    Ok(row.map(|(snapshot, revision)| (snapshot.0, revision as u64)))
}
