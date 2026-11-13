use chrono::{NaiveDate, Utc};
use kshift_core::{PlanActorRole, PlanCommand, PlanCommandEnvelope, PlanTaskDraft, ReportRange};
use kshift_plan_store::PlanSnapshotStore;
use sqlx::PgPool;
use uuid::Uuid;

#[tokio::test]
async fn persistent_plan_depth_survives_conflict_attachment_and_rollback() -> anyhow::Result<()> {
    let Ok(database_url) = std::env::var("KSHIFT_TEST_DATABASE_URL") else {
        eprintln!("KSHIFT_TEST_DATABASE_URL is not set; skipping PostgreSQL integration test");
        return Ok(());
    };
    let pool = PgPool::connect(&database_url).await?;
    let store = PlanSnapshotStore::new(pool.clone());
    store.migrate().await?;

    let suffix = Uuid::new_v4().simple().to_string();
    let project_id = Uuid::new_v4();
    let actor_id = Uuid::new_v4();
    let project_uuid = project_id.to_string();
    let actor_uuid = actor_id.to_string();
    insert_project(&pool, project_id, actor_id, &suffix).await?;

    let mut snapshot = kshift_core::demo_snapshot(NaiveDate::from_ymd_opt(2026, 11, 13).unwrap());
    snapshot.project.id = project_uuid.clone();
    snapshot.project.revision = 7;
    for person in &mut snapshot.people {
        if person.id == "d0000000-0000-4000-8000-000000000002" {
            person.id = actor_uuid.clone();
        }
    }
    for task in &mut snapshot.tasks {
        task.project_id = project_uuid.clone();
        if task.assignee_id.as_deref() == Some("d0000000-0000-4000-8000-000000000002") {
            task.assignee_id = Some(actor_uuid.clone());
        }
    }
    for entry in &mut snapshot.history {
        if entry.actor_id == "d0000000-0000-4000-8000-000000000002" {
            entry.actor_id = actor_uuid.clone();
        }
    }
    store.initialize(&snapshot, actor_id).await?;
    let target_digest = snapshot.content_sha256();

    let create = PlanCommandEnvelope {
        request_id: format!("create-{suffix}"),
        project_id,
        expected_revision: 7,
        actor_id: actor_uuid.clone(),
        actor_role: PlanActorRole::Editor,
        command: PlanCommand::CreateTask {
            task_id: format!("task-{suffix}"),
            draft: PlanTaskDraft {
                parent_id: None,
                title: "持久化测试任务".to_owned(),
                description_markdown: "### markdown\n\n- item".to_owned(),
                status: kshift_core::TaskStatus::Todo,
                priority: kshift_core::TaskPriority::High,
                assignee_id: Some(actor_uuid.clone()),
                starts_on: NaiveDate::from_ymd_opt(2026, 11, 13).unwrap(),
                due_on: NaiveDate::from_ymd_opt(2026, 11, 15).unwrap(),
                estimate_minutes: 90,
                position: 9,
            },
        },
    };
    let created = store.execute(create).await?;
    assert!(created.ok);
    assert_eq!(created.snapshot.project.revision, 8);

    let reloaded = store.load(project_id).await?;
    assert!(reloaded
        .snapshot()
        .tasks
        .iter()
        .any(|task| task.title == "持久化测试任务"));

    let stale = store
        .execute(PlanCommandEnvelope {
            request_id: format!("stale-{suffix}"),
            project_id,
            expected_revision: 7,
            actor_id: actor_uuid.clone(),
            actor_role: PlanActorRole::Editor,
            command: PlanCommand::CreateTask {
                task_id: format!("stale-task-{suffix}"),
                draft: PlanTaskDraft {
                    parent_id: None,
                    title: "不应写入".to_owned(),
                    description_markdown: String::new(),
                    status: kshift_core::TaskStatus::Todo,
                    priority: kshift_core::TaskPriority::Low,
                    assignee_id: None,
                    starts_on: NaiveDate::from_ymd_opt(2026, 11, 13).unwrap(),
                    due_on: NaiveDate::from_ymd_opt(2026, 11, 13).unwrap(),
                    estimate_minutes: 10,
                    position: 10,
                },
            },
        })
        .await?;
    assert!(!stale.ok);
    assert_eq!(stale.error.unwrap().code, "revision_conflict");

    let task_id = created
        .snapshot
        .tasks
        .iter()
        .find(|task| task.title == "持久化测试任务")
        .unwrap()
        .id
        .clone();
    let content = b"# attachment\n\nsha256".to_vec();
    let attached = store
        .execute(PlanCommandEnvelope {
            request_id: format!("attach-{suffix}"),
            project_id,
            expected_revision: 8,
            actor_id: actor_uuid.clone(),
            actor_role: PlanActorRole::Editor,
            command: PlanCommand::AttachFile {
                task_id,
                expected_version: 1,
                filename: "evidence.md".to_owned(),
                declared_media_type: "text/markdown".to_owned(),
                content: content.clone(),
            },
        })
        .await?;
    assert!(attached.ok);
    assert_eq!(attached.snapshot.project.revision, 9);
    let digest = attached.snapshot.attachments.last().unwrap().sha256.clone();
    assert_eq!(store.attachment(project_id, &digest).await?, Some(content));

    let rolled_back = store
        .execute(PlanCommandEnvelope {
            request_id: format!("rollback-{suffix}"),
            project_id,
            expected_revision: 9,
            actor_id: actor_uuid,
            actor_role: PlanActorRole::Admin,
            command: PlanCommand::Rollback {
                target_revision: 7,
                reason: "恢复持久化证据".to_owned(),
            },
        })
        .await?;
    assert!(rolled_back.ok);
    assert_eq!(rolled_back.snapshot.project.revision, 10);
    let audit = &rolled_back.snapshot.history[0];
    assert_eq!(audit.action, "rollback");
    assert_eq!(audit.restored_from_revision, Some(7));
    assert_eq!(audit.content_sha256, target_digest);

    let restarted = store.load(project_id).await?;
    assert_eq!(restarted.snapshot().project.revision, 10);
    assert!(restarted
        .snapshot()
        .tasks
        .iter()
        .all(|task| task.title != "持久化测试任务"));
    let report = store
        .report(
            project_id,
            &ReportRange {
                starts_on: NaiveDate::from_ymd_opt(2026, 11, 10).unwrap(),
                ends_on: NaiveDate::from_ymd_opt(2026, 11, 20).unwrap(),
            },
            NaiveDate::from_ymd_opt(2026, 11, 13).unwrap(),
        )
        .await?;
    assert_eq!(report.source_revision, 10);
    Ok(())
}

async fn insert_project(
    pool: &PgPool,
    project_id: Uuid,
    actor_id: Uuid,
    suffix: &str,
) -> anyhow::Result<()> {
    let now = Utc::now();
    sqlx::query(
        "INSERT INTO kshift.app_user (id, display_name, is_admin, is_active, created_at)
         VALUES ($1, $2, true, true, $3)",
    )
    .bind(actor_id)
    .bind(format!("R3 test {suffix}"))
    .bind(now)
    .execute(pool)
    .await?;
    sqlx::query(
        "INSERT INTO kshift.project (
            id, name, current_revision, created_by, created_at, updated_at
         ) VALUES ($1, $2, 7, $3, $4, $4)",
    )
    .bind(project_id)
    .bind(format!("R3 project {suffix}"))
    .bind(actor_id)
    .bind(now)
    .execute(pool)
    .await?;
    sqlx::query(
        "INSERT INTO kshift.project_member (
            project_id, user_id, role, created_at, updated_at
         ) VALUES ($1, $2, 'owner', $3, $3)",
    )
    .bind(project_id)
    .bind(actor_id)
    .bind(now)
    .execute(pool)
    .await?;
    Ok(())
}
