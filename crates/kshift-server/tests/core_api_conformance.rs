use std::collections::HashMap;

use contract::{parse_execute_command, v1, KshiftService};
use kshift_server::core_api::{CoreApi, CoreCommandRequest, CoreError, ExecutionContext};
use tonic::Code;
use uuid::Uuid;

mod common;

use common::*;

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn core_api_and_grpc_share_revision_and_idempotency() {
    let Some(db) = TestDatabase::create().await else {
        return;
    };
    let admin_id = Uuid::new_v4();
    let outsider_id = Uuid::new_v4();
    db.seed_user(admin_id, "Admin", true).await;
    db.seed_user(outsider_id, "Outsider", false).await;
    let api = TestApi::create(
        db.pool.clone(),
        HashMap::from([
            (admin_id, "admin-token".to_owned()),
            (outsider_id, "outsider-token".to_owned()),
        ]),
    );
    let project_id = Uuid::new_v4();

    KshiftService::execute_command(
        &api.api,
        request(
            create_project(project_id, Uuid::new_v4(), "Core API"),
            api.token(admin_id),
        ),
    )
    .await
    .expect("project creation should succeed");

    let task_request = create_task(
        project_id,
        Uuid::new_v4(),
        Uuid::new_v4(),
        "Core API task",
        "Created through the typed boundary",
        1,
    );
    let parsed = parse_execute_command(&task_request).expect("task command should parse");
    let context = ExecutionContext::new(admin_id, true, Uuid::new_v4());
    let outcome = CoreApi::execute_command(
        &api.api,
        &context,
        CoreCommandRequest {
            envelope: parsed.envelope,
            request_digest: parsed.request_digest,
        },
    )
    .await
    .expect("core command should succeed");
    assert_eq!(outcome.project_revision, 2);

    let core_snapshot = CoreApi::project_snapshot(&api.api, &context, project_id)
        .await
        .expect("core snapshot should succeed");
    assert_eq!(core_snapshot.project.current_revision, 2);
    assert_eq!(core_snapshot.tasks.len(), 1);
    assert_eq!(core_snapshot.tasks[0].title, "Core API task");

    let grpc_replay =
        KshiftService::execute_command(&api.api, request(task_request, api.token(admin_id)))
            .await
            .expect("idempotent gRPC replay should succeed")
            .into_inner();
    assert_eq!(response_revision(&grpc_replay), 2);

    let grpc_snapshot = KshiftService::get_project_snapshot(
        &api.api,
        request(
            v1::GetProjectSnapshotRequest {
                project_id: project_id.to_string(),
            },
            api.token(admin_id),
        ),
    )
    .await
    .expect("gRPC snapshot should succeed")
    .into_inner();
    assert_eq!(grpc_snapshot.revision, 2);

    let core_projects = CoreApi::list_projects(&api.api, &context)
        .await
        .expect("core project list should succeed");
    let grpc_projects = KshiftService::list_projects(
        &api.api,
        request(v1::ListProjectsRequest {}, api.token(admin_id)),
    )
    .await
    .expect("gRPC project list should succeed")
    .into_inner();
    assert_eq!(core_projects.len(), grpc_projects.projects.len());
    assert_eq!(
        core_projects[0].id.to_string(),
        grpc_projects.projects[0].id
    );

    let outsider_context = ExecutionContext::new(outsider_id, false, Uuid::new_v4());
    let core_denied = CoreApi::project_snapshot(&api.api, &outsider_context, project_id).await;
    assert!(matches!(core_denied, Err(CoreError::PermissionDenied)));
    let grpc_denied = KshiftService::get_project_snapshot(
        &api.api,
        request(
            v1::GetProjectSnapshotRequest {
                project_id: project_id.to_string(),
            },
            api.token(outsider_id),
        ),
    )
    .await
    .expect_err("outsider snapshot must fail");
    assert_eq!(grpc_denied.code(), Code::PermissionDenied);

    db.cleanup().await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn core_api_and_grpc_return_the_same_conflict_semantics() {
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

    KshiftService::execute_command(
        &api.api,
        request(
            create_project(project_id, Uuid::new_v4(), "Conflict"),
            api.token(admin_id),
        ),
    )
    .await
    .expect("project creation should succeed");

    let created = KshiftService::execute_command(
        &api.api,
        request(
            create_task(
                project_id,
                Uuid::new_v4(),
                Uuid::new_v4(),
                "Versioned task",
                "",
                1,
            ),
            api.token(admin_id),
        ),
    )
    .await
    .expect("task creation should succeed")
    .into_inner();
    let task = created_task(created);
    let task_id = Uuid::parse_str(&task.id).expect("task id should parse");

    let stale_update = update_task_title(
        project_id,
        Uuid::new_v4(),
        task_id,
        "Should not commit",
        2,
        2,
    );
    let parsed = parse_execute_command(&stale_update).expect("update command should parse");
    let context = ExecutionContext::new(admin_id, true, Uuid::new_v4());
    let outcome = CoreApi::execute_command(
        &api.api,
        &context,
        CoreCommandRequest {
            envelope: parsed.envelope,
            request_digest: parsed.request_digest,
        },
    )
    .await;
    assert!(matches!(outcome, Err(CoreError::Conflict { .. })));

    let grpc_error =
        KshiftService::execute_command(&api.api, request(stale_update, api.token(admin_id)))
            .await
            .expect_err("stale gRPC update must fail");
    assert_eq!(grpc_error.code(), Code::Aborted);

    let snapshot = KshiftService::get_project_snapshot(
        &api.api,
        request(
            v1::GetProjectSnapshotRequest {
                project_id: project_id.to_string(),
            },
            api.token(admin_id),
        ),
    )
    .await
    .expect("snapshot should succeed")
    .into_inner();
    assert_eq!(snapshot.revision, 2);
    assert_eq!(snapshot.tasks[0].title, "Versioned task");

    db.cleanup().await;
}
