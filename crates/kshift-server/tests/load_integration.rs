use std::{
    collections::HashMap,
    time::{Duration, Instant},
};

use contract::{v1, KshiftService};
use futures_util::future::join_all;
use kshift_server::config::ApiLimits;
use uuid::Uuid;

mod common;

use common::*;

#[tokio::test(flavor = "multi_thread", worker_threads = 16)]
async fn two_times_target_concurrency_holds() {
    let Some(db) = TestDatabase::create().await else {
        return;
    };
    let admin_id = Uuid::new_v4();
    db.seed_user(admin_id, "Load Admin", true).await;
    let mut tokens = HashMap::from([(admin_id, "admin-token".to_owned())]);
    let mut editors = Vec::new();
    for index in 0..40 {
        let user_id = Uuid::new_v4();
        db.seed_user(user_id, &format!("Editor {index}"), false)
            .await;
        tokens.insert(user_id, format!("editor-token-{index}"));
        editors.push(user_id);
    }

    let token_map = tokens.clone();
    let api = TestApi::create_with_limits(
        db.pool.clone(),
        tokens,
        ApiLimits {
            unary_rpc: 200,
            write_transactions: 16,
            event_streams: 64,
            streams_per_user: 1,
        },
    );
    let admin_token = api.token(admin_id).to_owned();
    let mut projects = Vec::new();
    for (index, editor_id) in editors.iter().enumerate() {
        let project_id = Uuid::new_v4();
        api.api
            .execute_command(request(
                create_project(project_id, Uuid::new_v4(), &format!("Load {index}")),
                &admin_token,
            ))
            .await
            .expect("project should be created");
        api.api
            .execute_command(request(
                add_member(
                    project_id,
                    Uuid::new_v4(),
                    *editor_id,
                    v1::ProjectRole::Editor,
                    1,
                ),
                &admin_token,
            ))
            .await
            .expect("editor should be added");
        projects.push(project_id);
    }

    let snapshot_futures = (0..100).map(|index| {
        let api = api.api.clone();
        let token = token_map
            .get(&editors[index % editors.len()])
            .expect("reader token should exist")
            .clone();
        let project_id = projects[index % projects.len()];
        async move {
            api.get_project_snapshot(request(
                v1::GetProjectSnapshotRequest {
                    project_id: project_id.to_string(),
                },
                &token,
            ))
            .await
            .is_ok()
        }
    });
    let snapshots = join_all(snapshot_futures).await;
    assert!(snapshots.iter().all(|result| *result));

    let duration_secs = std::env::var("KSHIFT_LOAD_DURATION_SECS")
        .ok()
        .and_then(|value| value.parse::<u64>().ok())
        .unwrap_or(1)
        .max(1);
    let started = Instant::now();
    let mut waves = 0_u64;
    let mut writes_completed = 0_u64;
    while waves == 0 || started.elapsed() < Duration::from_secs(duration_secs) {
        let expected_revision = 2 + waves;
        for (offset, chunk) in projects.chunks(16).enumerate() {
            let futures = chunk.iter().enumerate().map(|(chunk_index, project_id)| {
                let api = api.api.clone();
                let token = token_map
                    .get(&editors[offset * 16 + chunk_index])
                    .expect("editor token should exist")
                    .clone();
                let project_id = *project_id;
                let command_id = Uuid::new_v4();
                async move {
                    api.execute_command(request(
                        create_task(
                            project_id,
                            command_id,
                            Uuid::new_v4(),
                            "Load task",
                            "",
                            expected_revision,
                        ),
                        &token,
                    ))
                    .await
                    .is_ok()
                }
            });
            let writes = join_all(futures).await;
            assert!(
                writes.iter().all(|result| *result),
                "all writer transactions in the current wave should succeed"
            );
            writes_completed += writes.len() as u64;
        }
        waves += 1;
    }
    assert!(
        duration_secs > 30 || started.elapsed().as_secs() < 30,
        "the default short load run should complete in bounded time"
    );
    let report = serde_json::json!({
        "status": "passed",
        "duration_secs": duration_secs,
        "waves": waves,
        "editors": editors.len(),
        "snapshot_requests": 100,
        "writes_completed": writes_completed,
        "elapsed_secs": started.elapsed().as_secs(),
    });
    if let Ok(path) = std::env::var("KSHIFT_LOAD_REPORT") {
        std::fs::write(path, format!("{report}\n")).expect("load report should be written");
    }
    db.cleanup().await;
}
