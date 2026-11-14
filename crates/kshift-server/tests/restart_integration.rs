use std::collections::HashMap;

use contract::{v1, KshiftService};
use futures_util::StreamExt;
use uuid::Uuid;

mod common;

use common::*;

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn api_restart_replays_outbox_and_continues_revision() {
    let Some(db) = TestDatabase::create().await else {
        return;
    };
    let admin_id = Uuid::new_v4();
    db.seed_user(admin_id, "Restart Admin", true).await;
    let tokens = HashMap::from([(admin_id, "restart-admin-token".to_owned())]);
    let first_api = TestApi::create(db.pool.clone(), tokens.clone());
    let project_id = Uuid::new_v4();
    first_api
        .api
        .execute_command(request(
            create_project(project_id, Uuid::new_v4(), "Restart"),
            first_api.token(admin_id),
        ))
        .await
        .expect("project should be created");
    first_api
        .api
        .execute_command(request(
            create_task(project_id, Uuid::new_v4(), Uuid::new_v4(), "Before", "", 1),
            first_api.token(admin_id),
        ))
        .await
        .expect("first task should be created");

    let mut before = first_api
        .api
        .watch_project_changes(request(
            v1::WatchProjectChangesRequest {
                project_id: project_id.to_string(),
                since_revision: 1,
            },
            first_api.token(admin_id),
        ))
        .await
        .expect("first watch should open")
        .into_inner();
    let first_event = before
        .next()
        .await
        .expect("first event should arrive")
        .unwrap();
    match first_event.payload {
        Some(v1::watch_project_changes_response::Payload::Event(event)) => {
            assert_eq!(event.revision, 2);
        }
        other => panic!("expected first event, got {other:?}"),
    }
    drop(before);
    drop(first_api);

    let second_api = TestApi::create(db.pool.clone(), tokens);
    let second_task = second_api
        .api
        .execute_command(request(
            create_task(project_id, Uuid::new_v4(), Uuid::new_v4(), "After", "", 2),
            second_api.token(admin_id),
        ))
        .await
        .expect("write should continue after restart")
        .into_inner();
    assert_eq!(response_revision(&second_task), 3);

    let mut after = second_api
        .api
        .watch_project_changes(request(
            v1::WatchProjectChangesRequest {
                project_id: project_id.to_string(),
                since_revision: 2,
            },
            second_api.token(admin_id),
        ))
        .await
        .expect("second watch should open")
        .into_inner();
    let second_event = after
        .next()
        .await
        .expect("second event should arrive")
        .unwrap();
    match second_event.payload {
        Some(v1::watch_project_changes_response::Payload::Event(event)) => {
            assert_eq!(event.revision, 3);
        }
        other => panic!("expected second event, got {other:?}"),
    }

    let snapshot = second_api
        .api
        .get_project_snapshot(request(
            v1::GetProjectSnapshotRequest {
                project_id: project_id.to_string(),
            },
            second_api.token(admin_id),
        ))
        .await
        .expect("snapshot should be readable after restart")
        .into_inner();
    assert_eq!(snapshot.revision, 3);
    assert_eq!(snapshot.tasks.len(), 2);

    db.cleanup().await;
}
