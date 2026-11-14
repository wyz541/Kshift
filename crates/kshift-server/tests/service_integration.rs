use std::{
    collections::HashMap,
    io::Write,
    sync::{Arc, Mutex},
};

use contract::{error_detail, v1, KshiftService};
use domain::SCHEMA_VERSION;
use futures_util::StreamExt;
use tonic::Code;
use uuid::Uuid;

mod common;

use common::*;

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn project_isolation_and_member_access_are_enforced() {
    let Some(db) = TestDatabase::create().await else {
        return;
    };
    let admin_id = Uuid::new_v4();
    let member_id = Uuid::new_v4();
    db.seed_user(admin_id, "Admin", true).await;
    db.seed_user(member_id, "Member", false).await;
    let tokens = HashMap::from([
        (admin_id, "admin-token".to_owned()),
        (member_id, "member-token".to_owned()),
    ]);
    let api = TestApi::create(db.pool.clone(), tokens);
    let project_id = Uuid::new_v4();

    api.api
        .execute_command(request(
            create_project(project_id, Uuid::new_v4(), "Private"),
            api.token(admin_id),
        ))
        .await
        .expect("admin should create project");

    let member_projects = api
        .api
        .list_projects(request(v1::ListProjectsRequest {}, api.token(member_id)))
        .await
        .expect("project list should succeed")
        .into_inner();
    assert!(member_projects.projects.is_empty());

    let denied = api
        .api
        .get_project_snapshot(request(
            v1::GetProjectSnapshotRequest {
                project_id: project_id.to_string(),
            },
            api.token(member_id),
        ))
        .await
        .expect_err("non-member must not read the project");
    assert_eq!(denied.code(), Code::PermissionDenied);

    api.api
        .execute_command(request(
            add_member(
                project_id,
                Uuid::new_v4(),
                member_id,
                v1::ProjectRole::Viewer,
                1,
            ),
            api.token(admin_id),
        ))
        .await
        .expect("admin should add member");

    let snapshot = api
        .api
        .get_project_snapshot(request(
            v1::GetProjectSnapshotRequest {
                project_id: project_id.to_string(),
            },
            api.token(member_id),
        ))
        .await
        .expect("member should read the project")
        .into_inner();
    assert_eq!(snapshot.revision, 2);
    assert_eq!(snapshot.members.len(), 2);
    assert_eq!(snapshot.users.len(), 2);
    assert_eq!(snapshot.project.as_ref().unwrap().revision, 2);

    let member_projects = api
        .api
        .list_projects(request(v1::ListProjectsRequest {}, api.token(member_id)))
        .await
        .expect("project list should succeed")
        .into_inner();
    assert_eq!(member_projects.projects.len(), 1);
    assert_eq!(member_projects.projects[0].id, project_id.to_string());

    db.cleanup().await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn assignees_are_project_members_and_read_back_in_stable_order() {
    let Some(db) = TestDatabase::create().await else {
        return;
    };
    let admin_id = Uuid::new_v4();
    let first_member = Uuid::new_v4();
    let second_member = Uuid::new_v4();
    let outsider = Uuid::new_v4();
    db.seed_user(admin_id, "Admin", true).await;
    db.seed_user(first_member, "First", false).await;
    db.seed_user(second_member, "Second", false).await;
    db.seed_user(outsider, "Outsider", false).await;
    let api = TestApi::create(
        db.pool.clone(),
        HashMap::from([(admin_id, "admin-token".to_owned())]),
    );
    let project_id = Uuid::new_v4();

    api.api
        .execute_command(request(
            create_project(project_id, Uuid::new_v4(), "Shared ownership"),
            api.token(admin_id),
        ))
        .await
        .unwrap();
    for (revision, member_id) in [(1, first_member), (2, second_member)] {
        api.api
            .execute_command(request(
                add_member(
                    project_id,
                    Uuid::new_v4(),
                    member_id,
                    v1::ProjectRole::Editor,
                    revision,
                ),
                api.token(admin_id),
            ))
            .await
            .unwrap();
    }

    let task = created_task(
        api.api
            .execute_command(request(
                create_task_with_assignees(
                    project_id,
                    Uuid::new_v4(),
                    "Two owners",
                    3,
                    vec![second_member, first_member],
                ),
                api.token(admin_id),
            ))
            .await
            .unwrap()
            .into_inner(),
    );
    let mut expected = vec![first_member.to_string(), second_member.to_string()];
    expected.sort();
    assert_eq!(task.assignee_ids, expected);

    let error = api
        .api
        .execute_command(request(
            create_task_with_assignees(
                project_id,
                Uuid::new_v4(),
                "Invalid owner",
                4,
                vec![first_member, outsider],
            ),
            api.token(admin_id),
        ))
        .await
        .expect_err("non-project members must not be assignees");
    assert_eq!(error.code(), Code::InvalidArgument);

    db.cleanup().await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn concurrent_writes_do_not_silently_overwrite() {
    let Some(db) = TestDatabase::create().await else {
        return;
    };
    let admin_id = Uuid::new_v4();
    db.seed_user(admin_id, "Admin", true).await;
    let api = TestApi::create(
        db.pool.clone(),
        HashMap::from([(admin_id, "admin-token".to_owned())]),
    );
    let project_id = Uuid::new_v4();

    api.api
        .execute_command(request(
            create_project(project_id, Uuid::new_v4(), "Concurrency"),
            api.token(admin_id),
        ))
        .await
        .expect("project should be created");
    let task = created_task(
        api.api
            .execute_command(request(
                create_task(project_id, Uuid::new_v4(), Uuid::new_v4(), "Initial", "", 1),
                api.token(admin_id),
            ))
            .await
            .expect("task should be created")
            .into_inner(),
    );
    assert_eq!(task.version, 1);
    let task_id = Uuid::parse_str(&task.id).unwrap();

    let first = api.api.execute_command(request(
        update_task_title(project_id, Uuid::new_v4(), task_id, "Writer A", 2, 1),
        api.token(admin_id),
    ));
    let second = api.api.execute_command(request(
        update_task_title(project_id, Uuid::new_v4(), task_id, "Writer B", 2, 1),
        api.token(admin_id),
    ));
    let (first, second) = tokio::join!(first, second);
    let success_count = usize::from(first.is_ok()) + usize::from(second.is_ok());
    assert_eq!(success_count, 1, "exactly one concurrent writer must win");

    let conflict = first
        .err()
        .or_else(|| second.err())
        .expect("one write must conflict");
    assert_eq!(conflict.code(), Code::Aborted);
    let detail = error_detail(&conflict).expect("conflict detail should decode");
    assert_eq!(detail.code, v1::ErrorCode::Conflict as i32);
    assert_eq!(detail.current_project_revision, Some(3));

    let snapshot = api
        .api
        .get_project_snapshot(request(
            v1::GetProjectSnapshotRequest {
                project_id: project_id.to_string(),
            },
            api.token(admin_id),
        ))
        .await
        .expect("snapshot should succeed")
        .into_inner();
    assert_eq!(snapshot.revision, 3);
    assert!(matches!(
        snapshot.tasks[0].title.as_str(),
        "Writer A" | "Writer B"
    ));

    db.cleanup().await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn snapshot_maps_task_history_and_project_audit() {
    let Some(db) = TestDatabase::create().await else {
        return;
    };
    let admin_id = Uuid::new_v4();
    db.seed_user(admin_id, "Audit User", true).await;
    let api = TestApi::create(
        db.pool.clone(),
        HashMap::from([(admin_id, "audit-token".to_owned())]),
    );
    let project_id = Uuid::new_v4();

    api.api
        .execute_command(request(
            create_project(project_id, Uuid::new_v4(), "Audit Project"),
            api.token(admin_id),
        ))
        .await
        .expect("project should be created");
    let task = created_task(
        api.api
            .execute_command(request(
                create_task(
                    project_id,
                    Uuid::new_v4(),
                    Uuid::new_v4(),
                    "Initial audit task",
                    "",
                    1,
                ),
                api.token(admin_id),
            ))
            .await
            .expect("task should be created")
            .into_inner(),
    );
    let task_id = Uuid::parse_str(&task.id).expect("task id should be a UUID");

    api.api
        .execute_command(request(
            update_task_title(
                project_id,
                Uuid::new_v4(),
                task_id,
                "Updated audit task",
                2,
                1,
            ),
            api.token(admin_id),
        ))
        .await
        .expect("task should be updated");

    let snapshot = api
        .api
        .get_project_snapshot(request(
            v1::GetProjectSnapshotRequest {
                project_id: project_id.to_string(),
            },
            api.token(admin_id),
        ))
        .await
        .expect("snapshot should include audit data")
        .into_inner();

    assert_eq!(snapshot.revision, 3);
    assert_eq!(snapshot.audit.len(), 3);
    assert_eq!(snapshot.audit[0].action, "create_project");
    assert_eq!(snapshot.audit[0].summary, "创建项目 Audit Project");
    assert_eq!(snapshot.audit[0].revision, Some(1));
    assert_eq!(snapshot.audit[1].action, "create_task");
    assert_eq!(snapshot.audit[1].summary, "创建任务 Initial audit task");
    assert_eq!(snapshot.audit[1].revision, Some(2));
    assert_eq!(snapshot.audit[1].task_id.as_deref(), Some(task.id.as_str()));
    assert_eq!(snapshot.audit[2].action, "update_task");
    assert_eq!(snapshot.audit[2].summary, "更新任务 Updated audit task");
    assert_eq!(snapshot.audit[2].revision, Some(3));
    assert_eq!(snapshot.audit[2].actor_id, admin_id.to_string());

    db.cleanup().await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn batch_status_update_is_atomic() {
    let Some(db) = TestDatabase::create().await else {
        return;
    };
    let admin_id = Uuid::new_v4();
    db.seed_user(admin_id, "Admin", true).await;
    let api = TestApi::create(
        db.pool.clone(),
        HashMap::from([(admin_id, "admin-token".to_owned())]),
    );
    let project_id = Uuid::new_v4();

    api.api
        .execute_command(request(
            create_project(project_id, Uuid::new_v4(), "Batch"),
            api.token(admin_id),
        ))
        .await
        .expect("project should be created");
    let first = created_task(
        api.api
            .execute_command(request(
                create_task(project_id, Uuid::new_v4(), Uuid::new_v4(), "First", "", 1),
                api.token(admin_id),
            ))
            .await
            .expect("first task should be created")
            .into_inner(),
    );
    let second = created_task(
        api.api
            .execute_command(request(
                create_task(project_id, Uuid::new_v4(), Uuid::new_v4(), "Second", "", 2),
                api.token(admin_id),
            ))
            .await
            .expect("second task should be created")
            .into_inner(),
    );
    let first_id = Uuid::parse_str(&first.id).unwrap();
    let second_id = Uuid::parse_str(&second.id).unwrap();

    let response = api
        .api
        .execute_command(request(
            batch_update_status(
                project_id,
                Uuid::new_v4(),
                vec![(first_id, 1), (second_id, 1)],
                v1::TaskStatus::Done,
                3,
            ),
            api.token(admin_id),
        ))
        .await
        .expect("batch should commit")
        .into_inner();
    assert_eq!(response_revision(&response), 4);
    let event = response
        .result
        .and_then(|result| result.event)
        .expect("batch event should be present");
    assert_eq!(event.changes.len(), 2);

    let conflict = api
        .api
        .execute_command(request(
            batch_update_status(
                project_id,
                Uuid::new_v4(),
                vec![(first_id, 2), (second_id, 1)],
                v1::TaskStatus::Todo,
                4,
            ),
            api.token(admin_id),
        ))
        .await
        .expect_err("a stale entity version must reject the batch");
    assert_eq!(conflict.code(), Code::Aborted);

    let snapshot = api
        .api
        .get_project_snapshot(request(
            v1::GetProjectSnapshotRequest {
                project_id: project_id.to_string(),
            },
            api.token(admin_id),
        ))
        .await
        .expect("snapshot should succeed")
        .into_inner();
    assert_eq!(snapshot.revision, 4);
    assert!(snapshot
        .tasks
        .iter()
        .all(|task| task.status == v1::TaskStatus::Done as i32));

    db.cleanup().await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn idempotent_command_replays_without_second_write() {
    let Some(db) = TestDatabase::create().await else {
        return;
    };
    let admin_id = Uuid::new_v4();
    db.seed_user(admin_id, "Admin", true).await;
    let api = TestApi::create(
        db.pool.clone(),
        HashMap::from([(admin_id, "admin-token".to_owned())]),
    );
    let project_id = Uuid::new_v4();
    let task_id = Uuid::new_v4();
    let command_id = Uuid::new_v4();

    api.api
        .execute_command(request(
            create_project(project_id, Uuid::new_v4(), "Idempotency"),
            api.token(admin_id),
        ))
        .await
        .expect("project should be created");
    let command = create_task(project_id, command_id, task_id, "Once", "body", 1);
    let first = api
        .api
        .execute_command(request(command.clone(), api.token(admin_id)))
        .await
        .expect("first command should succeed")
        .into_inner();
    let replay = api
        .api
        .execute_command(request(command, api.token(admin_id)))
        .await
        .expect("replay should succeed")
        .into_inner();
    assert_eq!(first, replay);

    let revision =
        sqlx::query_scalar::<_, i64>("SELECT current_revision FROM kshift.project WHERE id = $1")
            .bind(project_id)
            .fetch_one(&db.pool)
            .await
            .unwrap();
    let events = sqlx::query_scalar::<_, i64>(
        "SELECT count(*) FROM kshift.change_event WHERE command_id = $1",
    )
    .bind(command_id)
    .fetch_one(&db.pool)
    .await
    .unwrap();
    let results = sqlx::query_scalar::<_, i64>(
        "SELECT count(*) FROM kshift.command_result WHERE command_id = $1",
    )
    .bind(command_id)
    .fetch_one(&db.pool)
    .await
    .unwrap();
    let audits =
        sqlx::query_scalar::<_, i64>("SELECT count(*) FROM kshift.audit_log WHERE command_id = $1")
            .bind(command_id)
            .fetch_one(&db.pool)
            .await
            .unwrap();
    assert_eq!(revision, 2);
    assert_eq!(events, 1);
    assert_eq!(results, 1);
    assert_eq!(audits, 1);

    db.cleanup().await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn task_planning_fields_and_relations_round_trip() {
    let Some(db) = TestDatabase::create().await else {
        return;
    };
    let admin_id = Uuid::new_v4();
    db.seed_user(admin_id, "Admin", true).await;
    let api = TestApi::create(
        db.pool.clone(),
        HashMap::from([(admin_id, "admin-token".to_owned())]),
    );
    let project_id = Uuid::new_v4();
    api.api
        .execute_command(request(
            create_project(project_id, Uuid::new_v4(), "Planning"),
            api.token(admin_id),
        ))
        .await
        .unwrap();
    let dependency = created_task(
        api.api
            .execute_command(request(
                create_task(
                    project_id,
                    Uuid::new_v4(),
                    Uuid::new_v4(),
                    "Dependency",
                    "",
                    1,
                ),
                api.token(admin_id),
            ))
            .await
            .unwrap()
            .into_inner(),
    );
    let dependency_id = Uuid::parse_str(&dependency.id).unwrap();

    let linked = created_task(
        api.api
            .execute_command(request(
                v1::ExecuteCommandRequest {
                    command: Some(v1::CommandEnvelope {
                        client_id: Uuid::new_v4().to_string(),
                        command_id: Uuid::new_v4().to_string(),
                        project_id: project_id.to_string(),
                        expected_project_revision: Some(2),
                        command: Some(v1::command_envelope::Command::CreateTask(
                            v1::CreateTaskCommand {
                                draft: Some(v1::TaskDraft {
                                    title: "Linked".to_owned(),
                                    description_markdown: "Planning body".to_owned(),
                                    status: v1::TaskStatus::InProgress as i32,
                                    priority: v1::TaskPriority::High as i32,
                                    assignee_ids: vec![admin_id.to_string()],
                                    planned_on: "2026-11-20".to_owned(),
                                    starts_on: Some("2026-11-18".to_owned()),
                                    due_on: Some("2026-11-22".to_owned()),
                                    tags: vec!["alpha".to_owned()],
                                    parent_task_id: Some(dependency_id.to_string()),
                                    dependency_task_ids: vec![dependency_id.to_string()],
                                }),
                            },
                        )),
                    }),
                },
                api.token(admin_id),
            ))
            .await
            .unwrap()
            .into_inner(),
    );
    assert_eq!(linked.assignee_ids, vec![admin_id.to_string()]);
    assert_eq!(linked.tags, vec!["alpha"]);
    assert_eq!(linked.parent_task_id, Some(dependency_id.to_string()));
    assert_eq!(linked.dependency_task_ids, vec![dependency_id.to_string()]);

    let linked_id = Uuid::parse_str(&linked.id).unwrap();
    let updated = created_task(
        api.api
            .execute_command(request(
                v1::ExecuteCommandRequest {
                    command: Some(v1::CommandEnvelope {
                        client_id: Uuid::new_v4().to_string(),
                        command_id: Uuid::new_v4().to_string(),
                        project_id: project_id.to_string(),
                        expected_project_revision: Some(3),
                        command: Some(v1::command_envelope::Command::UpdateTask(
                            v1::UpdateTaskCommand {
                                task_id: linked_id.to_string(),
                                expected_entity_version: 1,
                                patch: Some(v1::TaskPatch {
                                    title: None,
                                    description_markdown: None,
                                    status: None,
                                    priority: None,
                                    assignee_ids: Some(v1::StringList { values: Vec::new() }),
                                    planned_on: None,
                                    starts_on: None,
                                    due_on: Some(String::new()),
                                    tags: Some(v1::StringList { values: Vec::new() }),
                                    parent_task_id: Some(String::new()),
                                    dependency_task_ids: Some(v1::StringList {
                                        values: Vec::new(),
                                    }),
                                }),
                            },
                        )),
                    }),
                },
                api.token(admin_id),
            ))
            .await
            .unwrap()
            .into_inner(),
    );
    assert!(updated.assignee_ids.is_empty());
    assert!(updated.tags.is_empty());
    assert!(updated.due_on.is_none());
    assert!(updated.parent_task_id.is_none());
    assert!(updated.dependency_task_ids.is_empty());
    assert_eq!(updated.version, 2);

    db.cleanup().await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn failed_transaction_rolls_back_business_and_outbox() {
    let Some(db) = TestDatabase::create().await else {
        return;
    };
    let admin_id = Uuid::new_v4();
    db.seed_user(admin_id, "Admin", true).await;
    let api = TestApi::create(
        db.pool.clone(),
        HashMap::from([(admin_id, "admin-token".to_owned())]),
    );
    let project_id = Uuid::new_v4();
    api.api
        .execute_command(request(
            create_project(project_id, Uuid::new_v4(), "Original"),
            api.token(admin_id),
        ))
        .await
        .expect("project should be created");

    let mut tx = db.pool.begin().await.unwrap();
    sqlx::query("UPDATE kshift.project SET name = 'Changed', current_revision = 2 WHERE id = $1")
        .bind(project_id)
        .execute(&mut *tx)
        .await
        .unwrap();
    let failure = sqlx::query(
        r#"
        INSERT INTO kshift.change_event (
            project_id, revision, schema_version, command_id, payload, created_at, expires_at
        )
        VALUES ($1, 2, $2, $3, NULL, now(), now() + interval '7 days')
        "#,
    )
    .bind(project_id)
    .bind(SCHEMA_VERSION as i32)
    .bind(Uuid::new_v4())
    .execute(&mut *tx)
    .await;
    assert!(failure.is_err(), "NULL payload should fail the transaction");
    drop(tx);

    let row = sqlx::query_as::<_, (String, i64)>(
        "SELECT name, current_revision FROM kshift.project WHERE id = $1",
    )
    .bind(project_id)
    .fetch_one(&db.pool)
    .await
    .unwrap();
    let revision_two_events = sqlx::query_scalar::<_, i64>(
        "SELECT count(*) FROM kshift.change_event WHERE project_id = $1 AND revision = 2",
    )
    .bind(project_id)
    .fetch_one(&db.pool)
    .await
    .unwrap();
    assert_eq!(row, ("Original".to_owned(), 1));
    assert_eq!(revision_two_events, 0);

    db.cleanup().await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn watch_replays_outbox_and_reports_retention_gap() {
    let Some(db) = TestDatabase::create().await else {
        return;
    };
    let admin_id = Uuid::new_v4();
    db.seed_user(admin_id, "Admin", true).await;
    let api = TestApi::create(
        db.pool.clone(),
        HashMap::from([(admin_id, "admin-token".to_owned())]),
    );
    let project_id = Uuid::new_v4();
    api.api
        .execute_command(request(
            create_project(project_id, Uuid::new_v4(), "Events"),
            api.token(admin_id),
        ))
        .await
        .unwrap();
    let task = created_task(
        api.api
            .execute_command(request(
                create_task(project_id, Uuid::new_v4(), Uuid::new_v4(), "First", "", 1),
                api.token(admin_id),
            ))
            .await
            .unwrap()
            .into_inner(),
    );
    let task_id = Uuid::parse_str(&task.id).unwrap();

    let mut stream = api
        .api
        .watch_project_changes(request(
            v1::WatchProjectChangesRequest {
                project_id: project_id.to_string(),
                since_revision: 1,
            },
            api.token(admin_id),
        ))
        .await
        .expect("watch should open")
        .into_inner();
    let event = stream.next().await.unwrap().unwrap();
    match event.payload {
        Some(v1::watch_project_changes_response::Payload::Event(event)) => {
            assert_eq!(event.revision, 2);
            assert!(matches!(
                event
                    .changes
                    .first()
                    .and_then(|change| change.change.as_ref()),
                Some(v1::change::Change::TaskUpserted(_))
            ));
        }
        other => panic!("expected change event, got {other:?}"),
    }
    drop(stream);

    api.api
        .execute_command(request(
            update_task_title(project_id, Uuid::new_v4(), task_id, "Second", 2, 1),
            api.token(admin_id),
        ))
        .await
        .unwrap();
    sqlx::query("DELETE FROM kshift.change_event WHERE project_id = $1 AND revision < 3")
        .bind(project_id)
        .execute(&db.pool)
        .await
        .unwrap();

    let mut stream = api
        .api
        .watch_project_changes(request(
            v1::WatchProjectChangesRequest {
                project_id: project_id.to_string(),
                since_revision: 1,
            },
            api.token(admin_id),
        ))
        .await
        .expect("watch should open")
        .into_inner();
    let reset = stream.next().await.unwrap().unwrap();
    match reset.payload {
        Some(v1::watch_project_changes_response::Payload::ResetRequired(reset)) => {
            assert_eq!(reset.current_revision, 3);
            assert_eq!(reset.minimum_retained_revision, 3);
            assert_eq!(reset.reason, "retention_gap");
        }
        other => panic!("expected reset required, got {other:?}"),
    }

    db.cleanup().await;
}

#[derive(Clone, Default)]
struct SharedBuffer(Arc<Mutex<Vec<u8>>>);

impl Write for SharedBuffer {
    fn write(&mut self, buffer: &[u8]) -> std::io::Result<usize> {
        let mut output = self
            .0
            .lock()
            .expect("log buffer lock should not be poisoned");
        output.extend_from_slice(buffer);
        Ok(buffer.len())
    }

    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

#[tokio::test(flavor = "current_thread")]
async fn logs_do_not_contain_token_or_command_body() {
    let Some(db) = TestDatabase::create().await else {
        return;
    };
    let admin_id = Uuid::new_v4();
    db.seed_user(admin_id, "Admin", true).await;
    let token = "super-secret-test-token";
    let api = TestApi::create(
        db.pool.clone(),
        HashMap::from([(admin_id, token.to_owned())]),
    );
    let project_id = Uuid::new_v4();
    let body = "SENSITIVE-COMMAND-BODY-DO-NOT-LOG";
    let buffer = SharedBuffer::default();
    let subscriber = tracing_subscriber::fmt()
        .json()
        .with_max_level(tracing::Level::INFO)
        .with_writer({
            let buffer = buffer.clone();
            move || buffer.clone()
        })
        .finish();

    let guard = tracing::subscriber::set_default(subscriber);
    api.api
        .execute_command(request(
            create_project(project_id, Uuid::new_v4(), "Logs"),
            token,
        ))
        .await
        .unwrap();
    api.api
        .execute_command(request(
            create_task(
                project_id,
                Uuid::new_v4(),
                Uuid::new_v4(),
                "Secret title",
                body,
                1,
            ),
            token,
        ))
        .await
        .unwrap();
    drop(guard);

    let output = String::from_utf8(
        buffer
            .0
            .lock()
            .expect("log buffer lock should not be poisoned")
            .clone(),
    )
    .unwrap();
    assert!(!output.contains(token));
    assert!(!output.contains(body));
    assert!(!output.contains("postgres://"));

    db.cleanup().await;
}
