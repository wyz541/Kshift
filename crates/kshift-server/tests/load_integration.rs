#![recursion_limit = "256"]

use std::{
    collections::{BTreeMap, HashMap},
    process::Command,
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc,
    },
    time::{Duration, Instant},
};

use chrono::Utc;
use contract::{v1, KshiftService};
use futures_util::{future::join_all, StreamExt};
use kshift_server::{config::ApiLimits, service::KshiftApi};
use serde_json::json;
use sqlx::PgPool;
use tokio::sync::mpsc;
use tokio_util::sync::CancellationToken;
use tonic::Code;
use uuid::Uuid;

mod common;

use common::*;

const EDITORS: usize = 40;
const WRITE_TRANSACTIONS: usize = 16;
const SNAPSHOT_BURST: usize = 200;
const LOAD_DB_CONNECTIONS: u32 = 20;
const RSS_GROWTH_LIMIT_KB: u64 = 128 * 1024;
const RSS_PEAK_LIMIT_KB: u64 = 256 * 1024;

#[derive(Default)]
struct ProcessMetrics {
    sample_count: u64,
    cpu_percent_sum: f64,
    cpu_percent_peak: f64,
    rss_kb_start: u64,
    rss_kb_end: u64,
    rss_kb_after_warmup: Option<u64>,
    rss_kb_peak: u64,
    database_connections_peak: i64,
    database_lock_waiters_peak: i64,
}

#[derive(Default)]
struct EventMetrics {
    count: u64,
    gap_count: u64,
    stream_errors: u64,
    delays_ms: Vec<f64>,
}

#[tokio::test(flavor = "multi_thread", worker_threads = 16)]
async fn two_times_target_concurrency_holds() {
    let Some(db) = TestDatabase::create_with_max_connections(LOAD_DB_CONNECTIONS).await else {
        return;
    };
    let duration_secs = env_u64("KSHIFT_LOAD_DURATION_SECS", 1).max(1);
    let wave_interval_ms = env_u64("KSHIFT_LOAD_WAVE_INTERVAL_MS", 1_000).max(1);

    let admin_id = Uuid::new_v4();
    db.seed_user(admin_id, "Load Admin", true).await;
    let mut tokens = HashMap::from([(admin_id, "admin-token".to_owned())]);
    let mut editors = Vec::new();
    for index in 0..EDITORS {
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
            unary_rpc: SNAPSHOT_BURST,
            write_transactions: WRITE_TRANSACTIONS,
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

    let (snapshot_success, snapshot_failures, mut rpc_failure_codes) =
        run_snapshot_burst(&api.api, &token_map, &editors, &projects, SNAPSHOT_BURST).await;
    assert_eq!(
        (snapshot_success, snapshot_failures),
        (SNAPSHOT_BURST as u64, 0),
        "all 200 snapshot RPCs should be admitted and complete: {rpc_failure_codes:?}"
    );

    let (burst_results, burst_success, burst_exhausted, burst_unexpected) =
        run_locked_write_burst(&api.api, &token_map, &editors, &projects, &db.pool).await;
    assert_eq!(
        burst_success, WRITE_TRANSACTIONS as u64,
        "the write semaphore should admit exactly 16 blocked transactions"
    );
    assert_eq!(
        burst_exhausted,
        (EDITORS - WRITE_TRANSACTIONS) as u64,
        "the other 24 simultaneous writers should receive RESOURCE_EXHAUSTED"
    );
    assert_eq!(
        burst_unexpected, 0,
        "the saturated burst should not return other errors"
    );

    let mut revisions = vec![2_u64; EDITORS];
    for (index, result) in burst_results {
        if let Ok(response) = result {
            revisions[index] = response_revision(&response.into_inner());
        }
    }

    let conflict_result =
        run_multi_editor_conflict(&api.api, &token_map, &admin_token, &editors).await;
    assert_eq!(
        conflict_result.successes, 1,
        "exactly one editor should win the shared revision"
    );
    assert_eq!(
        conflict_result.unexpected, 0,
        "all losing concurrent editors should receive a bounded conflict or capacity error"
    );
    assert!(
        conflict_result.conflicts > 0,
        "losing concurrent editors should receive a conflict"
    );
    assert_eq!(
        (
            conflict_result.snapshot_revision,
            conflict_result.snapshot_tasks
        ),
        (42, 1),
        "the project snapshot must contain only the winning task"
    );

    let event_project_id = projects[0];
    let event_token = api.token(editors[0]).to_owned();
    let mut event_stream = api
        .api
        .watch_project_changes(request(
            v1::WatchProjectChangesRequest {
                project_id: event_project_id.to_string(),
                since_revision: revisions[0],
            },
            &event_token,
        ))
        .await
        .expect("event stream should open")
        .into_inner();
    let event_count = Arc::new(AtomicU64::new(0));
    let event_count_for_task = event_count.clone();
    let event_stop = CancellationToken::new();
    let event_stop_for_task = event_stop.clone();
    let initial_event_revision = revisions[0];
    let event_task = tokio::spawn(async move {
        let mut metrics = EventMetrics::default();
        let mut last_revision = initial_event_revision;
        loop {
            tokio::select! {
                _ = event_stop_for_task.cancelled() => break,
                item = event_stream.next() => {
                    match item {
                        Some(Ok(response)) => {
                            let Some(v1::watch_project_changes_response::Payload::Event(event)) = response.payload else {
                                continue;
                            };
                            if event.revision != last_revision + 1 {
                                metrics.gap_count += 1;
                            }
                            last_revision = event.revision;
                            metrics.count += 1;
                            event_count_for_task.fetch_add(1, Ordering::Relaxed);
                            if let Some(committed_at) = event.committed_at {
                                if let Some(committed_at) = chrono::DateTime::<Utc>::from_timestamp(
                                    committed_at.seconds,
                                    committed_at.nanos as u32,
                                ) {
                                    let delay_ms = (Utc::now() - committed_at)
                                        .num_milliseconds()
                                        .max(0) as f64;
                                    metrics.delays_ms.push(delay_ms);
                                }
                            }
                        }
                        Some(Err(_)) => {
                            metrics.stream_errors += 1;
                            break;
                        }
                        None => break,
                    }
                }
            }
        }
        metrics
    });

    let sampler_stop = CancellationToken::new();
    let sampler = tokio::spawn(collect_process_metrics(
        db.pool.clone(),
        sampler_stop.clone(),
    ));

    let started = Instant::now();
    let mut waves = 0_u64;
    let mut sustained_attempts = 0_u64;
    let mut sustained_successes = 0_u64;
    let mut sustained_exhausted = 0_u64;
    let mut sustained_unexpected = 0_u64;
    let mut event_project_writes = 0_u64;
    let mut command_latencies_ms = Vec::new();
    let mut rpc_bursts = 1_u64;
    let mut rpc_requests = SNAPSHOT_BURST as u64;
    let mut rpc_failures = snapshot_failures;

    while waves == 0 || started.elapsed() < Duration::from_secs(duration_secs) {
        if waves > 0 && waves % 60 == 0 {
            let (success, failures, failure_codes) =
                run_snapshot_burst(&api.api, &token_map, &editors, &projects, SNAPSHOT_BURST).await;
            rpc_bursts += 1;
            rpc_requests += SNAPSHOT_BURST as u64;
            rpc_failures += failures;
            for (code, count) in failure_codes {
                *rpc_failure_codes.entry(code).or_default() += count;
            }
            assert_eq!(
                (success, failures),
                (SNAPSHOT_BURST as u64, 0),
                "the sustained snapshot burst should fully complete: {rpc_failure_codes:?}"
            );
        }

        let wave_started = Instant::now();
        let expected_revisions = revisions.clone();
        let writes = join_all((0..EDITORS).map(|index| {
            let api = api.api.clone();
            let token = token_map
                .get(&editors[index])
                .expect("editor token should exist")
                .clone();
            let project_id = projects[index];
            let expected_revision = expected_revisions[index];
            async move {
                let attempt_started = Instant::now();
                let result = api
                    .execute_command(request(
                        create_task(
                            project_id,
                            Uuid::new_v4(),
                            Uuid::new_v4(),
                            "Load task",
                            "",
                            expected_revision,
                        ),
                        &token,
                    ))
                    .await;
                (index, attempt_started.elapsed(), result)
            }
        }))
        .await;

        sustained_attempts += writes.len() as u64;
        for (index, latency, result) in writes {
            command_latencies_ms.push(latency.as_secs_f64() * 1_000.0);
            match result {
                Ok(response) => {
                    let response = response.into_inner();
                    let revision = response_revision(&response);
                    assert_eq!(
                        revision,
                        revisions[index] + 1,
                        "successful writes must advance one revision"
                    );
                    revisions[index] = revision;
                    sustained_successes += 1;
                    if index == 0 {
                        event_project_writes += 1;
                    }
                }
                Err(status) if status.code() == Code::ResourceExhausted => {
                    sustained_exhausted += 1;
                }
                Err(status) => {
                    sustained_unexpected += 1;
                    eprintln!(
                        "unexpected writer error on project {index}: {:?} {}",
                        status.code(),
                        status.message()
                    );
                }
            }
        }
        waves += 1;

        if waves % 60 == 0 {
            eprintln!(
                "load progress: waves={waves} attempts={sustained_attempts} successes={sustained_successes} resource_exhausted={sustained_exhausted} elapsed_secs={}",
                started.elapsed().as_secs()
            );
        }

        let target = Duration::from_millis(wave_interval_ms);
        if let Some(remaining) = target.checked_sub(wave_started.elapsed()) {
            tokio::time::sleep(remaining).await;
        }
    }

    let event_wait_started = Instant::now();
    while event_count.load(Ordering::Relaxed) < event_project_writes
        && event_wait_started.elapsed() < Duration::from_secs(15)
    {
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    event_stop.cancel();
    let event_metrics = event_task.await.expect("event consumer should join");
    sampler_stop.cancel();
    let process_metrics = sampler.await.expect("metrics sampler should join");

    assert_eq!(
        sustained_unexpected, 0,
        "sustained writes should return only success or RESOURCE_EXHAUSTED"
    );
    assert_eq!(
        sustained_attempts,
        sustained_successes + sustained_exhausted,
        "every bounded write attempt should have a recorded outcome"
    );
    assert_eq!(
        event_metrics.count, event_project_writes,
        "every successful event-project write should be delivered once"
    );
    assert_eq!(
        event_metrics.gap_count, 0,
        "the event stream must not have gaps"
    );
    assert_eq!(
        event_metrics.stream_errors, 0,
        "the event stream must stay connected for the full run"
    );
    assert_eq!(
        rpc_failures, 0,
        "all snapshot RPC bursts should complete without failures"
    );
    let rss_growth_kb = process_metrics
        .rss_kb_end
        .saturating_sub(process_metrics.rss_kb_start);
    let rss_after_warmup_kb = process_metrics
        .rss_kb_after_warmup
        .unwrap_or(process_metrics.rss_kb_end);
    let rss_post_warmup_growth_kb = process_metrics
        .rss_kb_end
        .saturating_sub(rss_after_warmup_kb);
    eprintln!(
        "load resource summary: rss_start_mb={:.2} rss_after_5m_mb={:.2} rss_end_mb={:.2} rss_peak_mb={:.2} cpu_avg={:.2} cpu_peak={:.2} db_connections_peak={}",
        process_metrics.rss_kb_start as f64 / 1024.0,
        rss_after_warmup_kb as f64 / 1024.0,
        process_metrics.rss_kb_end as f64 / 1024.0,
        process_metrics.rss_kb_peak as f64 / 1024.0,
        if process_metrics.sample_count == 0 {
            0.0
        } else {
            process_metrics.cpu_percent_sum / process_metrics.sample_count as f64
        },
        process_metrics.cpu_percent_peak,
        process_metrics.database_connections_peak
    );
    assert!(
        rss_post_warmup_growth_kb <= RSS_GROWTH_LIMIT_KB,
        "process RSS post-warmup growth exceeded {} MiB: {} MiB",
        RSS_GROWTH_LIMIT_KB / 1024,
        rss_post_warmup_growth_kb as f64 / 1024.0
    );
    assert!(
        process_metrics.rss_kb_peak <= RSS_PEAK_LIMIT_KB,
        "process RSS peak exceeded {} MiB: {} MiB",
        RSS_PEAK_LIMIT_KB / 1024,
        process_metrics.rss_kb_peak as f64 / 1024.0
    );

    command_latencies_ms.sort_by(f64::total_cmp);
    let mut event_delays_ms = event_metrics.delays_ms.clone();
    event_delays_ms.sort_by(f64::total_cmp);
    let report = json!({
        "status": "passed",
        "configured_duration_secs": duration_secs,
        "elapsed_secs": started.elapsed().as_secs_f64(),
        "wave_interval_ms": wave_interval_ms,
        "waves": waves,
        "editors": EDITORS,
        "projects": projects.len(),
        "write_transaction_limit": WRITE_TRANSACTIONS,
        "concurrent_snapshot_requests": SNAPSHOT_BURST,
        "snapshot_rpc_bursts": rpc_bursts,
        "snapshot_rpc_requests": rpc_requests,
        "snapshot_rpc_failures": rpc_failures,
        "snapshot_rpc_failure_codes": rpc_failure_codes,
        "saturated_write_attempts": EDITORS,
        "saturated_write_successes": burst_success,
        "saturated_resource_exhausted": burst_exhausted,
        "saturated_unexpected_errors": burst_unexpected,
        "multi_editor_attempts": EDITORS,
        "multi_editor_successes": conflict_result.successes,
        "multi_editor_conflicts": conflict_result.conflicts,
        "multi_editor_resource_exhausted": conflict_result.exhausted,
        "multi_editor_unexpected_errors": conflict_result.unexpected,
        "silent_overwrite": false,
        "sustained_write_attempts": sustained_attempts,
        "sustained_write_successes": sustained_successes,
        "sustained_resource_exhausted": sustained_exhausted,
        "sustained_unexpected_errors": sustained_unexpected,
        "command_latency_ms_p50": percentile(&command_latencies_ms, 0.50),
        "command_latency_ms_p95": percentile(&command_latencies_ms, 0.95),
        "command_latency_ms_max": command_latencies_ms.last().copied().unwrap_or(0.0),
        "event_streams": 1,
        "events_expected": event_project_writes,
        "events_received": event_metrics.count,
        "event_gaps": event_metrics.gap_count,
        "event_stream_errors": event_metrics.stream_errors,
        "event_reconnect_count": 0,
        "event_delay_ms_p50": percentile(&event_delays_ms, 0.50),
        "event_delay_ms_p95": percentile(&event_delays_ms, 0.95),
        "event_delay_ms_max": event_delays_ms.last().copied().unwrap_or(0.0),
        "process_samples": process_metrics.sample_count,
        "process_sample_interval_secs": 5,
        "process_cpu_percent_average": if process_metrics.sample_count == 0 {
            0.0
        } else {
            process_metrics.cpu_percent_sum / process_metrics.sample_count as f64
        },
        "process_cpu_percent_peak": process_metrics.cpu_percent_peak,
        "process_rss_mb_start": process_metrics.rss_kb_start as f64 / 1024.0,
        "process_rss_mb_end": process_metrics.rss_kb_end as f64 / 1024.0,
        "process_rss_mb_growth": rss_growth_kb as f64 / 1024.0,
        "process_rss_mb_after_5m": rss_after_warmup_kb as f64 / 1024.0,
        "process_rss_mb_post_warmup_growth": rss_post_warmup_growth_kb as f64 / 1024.0,
        "process_rss_post_warmup_growth_limit_mb": RSS_GROWTH_LIMIT_KB as f64 / 1024.0,
        "process_rss_mb_peak": process_metrics.rss_kb_peak as f64 / 1024.0,
        "process_rss_peak_limit_mb": RSS_PEAK_LIMIT_KB as f64 / 1024.0,
        "database_connections_peak": process_metrics.database_connections_peak,
        "database_lock_waiters_peak": process_metrics.database_lock_waiters_peak,
        "covered_boundaries": {
            "service_api_load": true,
            "persistent_network_clients": false,
            "max_event_streams": false
        }
    });
    if let Ok(path) = std::env::var("KSHIFT_LOAD_REPORT") {
        std::fs::write(path, format!("{report}\n")).expect("load report should be written");
    }
    println!("{report}");
    db.cleanup().await;
}

#[derive(Default)]
struct ConflictResult {
    successes: u64,
    conflicts: u64,
    exhausted: u64,
    unexpected: u64,
    snapshot_revision: u64,
    snapshot_tasks: usize,
}

async fn run_snapshot_burst(
    api: &KshiftApi,
    token_map: &HashMap<Uuid, String>,
    editors: &[Uuid],
    projects: &[Uuid],
    count: usize,
) -> (u64, u64, BTreeMap<String, u64>) {
    let futures = (0..count).map(|index| {
        let api = api.clone();
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
        }
    });
    let results = join_all(futures).await;
    let mut successes = 0_u64;
    let mut failure_codes = BTreeMap::new();
    for result in results {
        match result {
            Ok(_) => successes += 1,
            Err(status) => {
                *failure_codes
                    .entry(format!("{:?}", status.code()))
                    .or_default() += 1;
            }
        }
    }
    (
        successes,
        (count as u64).saturating_sub(successes),
        failure_codes,
    )
}

async fn run_locked_write_burst(
    api: &KshiftApi,
    token_map: &HashMap<Uuid, String>,
    editors: &[Uuid],
    projects: &[Uuid],
    pool: &PgPool,
) -> (
    Vec<(
        usize,
        Result<tonic::Response<v1::ExecuteCommandResponse>, tonic::Status>,
    )>,
    u64,
    u64,
    u64,
) {
    let mut lock_transaction = pool.begin().await.expect("lock transaction should begin");
    sqlx::query("LOCK TABLE kshift.project IN ACCESS EXCLUSIVE MODE")
        .execute(&mut *lock_transaction)
        .await
        .expect("load test should lock the project table");
    let (exhausted_tx, mut exhausted_rx) = mpsc::unbounded_channel();
    let mut handles = Vec::new();
    for index in 0..EDITORS {
        let api = api.clone();
        let token = token_map
            .get(&editors[index])
            .expect("editor token should exist")
            .clone();
        let project_id = projects[index];
        let exhausted_tx = exhausted_tx.clone();
        handles.push(tokio::spawn(async move {
            let result = api
                .execute_command(request(
                    create_task(project_id, Uuid::new_v4(), Uuid::new_v4(), "Burst", "", 2),
                    &token,
                ))
                .await;
            if result
                .as_ref()
                .err()
                .is_some_and(|status| status.code() == Code::ResourceExhausted)
            {
                let _ = exhausted_tx.send(());
            }
            (index, result)
        }));
    }
    drop(exhausted_tx);

    let observed_exhausted = tokio::time::timeout(Duration::from_secs(10), async {
        let mut observed = 0_u64;
        while observed < (EDITORS - WRITE_TRANSACTIONS) as u64 {
            if exhausted_rx.recv().await.is_none() {
                break;
            }
            observed += 1;
        }
        observed
    })
    .await
    .unwrap_or(0);
    lock_transaction
        .rollback()
        .await
        .expect("load test lock should release");

    let results = join_all(handles)
        .await
        .into_iter()
        .map(|result| result.expect("burst task should join"))
        .collect::<Vec<_>>();
    let mut successes = 0_u64;
    let mut exhausted = 0_u64;
    let mut unexpected = 0_u64;
    for (_, result) in &results {
        match result {
            Ok(_) => successes += 1,
            Err(status) if status.code() == Code::ResourceExhausted => exhausted += 1,
            Err(_) => unexpected += 1,
        }
    }
    assert_eq!(
        observed_exhausted,
        (EDITORS - WRITE_TRANSACTIONS) as u64,
        "the locked burst should reject exactly the writers beyond the semaphore limit"
    );
    (results, successes, exhausted, unexpected)
}

async fn run_multi_editor_conflict(
    api: &KshiftApi,
    token_map: &HashMap<Uuid, String>,
    admin_token: &str,
    editors: &[Uuid],
) -> ConflictResult {
    let project_id = Uuid::new_v4();
    api.execute_command(request(
        create_project(project_id, Uuid::new_v4(), "Concurrent Editors"),
        admin_token,
    ))
    .await
    .expect("conflict project should be created");
    let mut revision = 1_u64;
    for editor_id in editors {
        revision = response_revision(
            &api.execute_command(request(
                add_member(
                    project_id,
                    Uuid::new_v4(),
                    *editor_id,
                    v1::ProjectRole::Editor,
                    revision,
                ),
                admin_token,
            ))
            .await
            .expect("editor should be added to the conflict project")
            .into_inner(),
        );
    }
    assert_eq!(revision, 1 + EDITORS as u64);

    let expected_revision = revision;
    let writes = join_all(editors.iter().map(|editor_id| {
        let api = api.clone();
        let token = token_map
            .get(editor_id)
            .expect("editor token should exist")
            .clone();
        async move {
            api.execute_command(request(
                create_task(
                    project_id,
                    Uuid::new_v4(),
                    Uuid::new_v4(),
                    "One winner",
                    "",
                    expected_revision,
                ),
                &token,
            ))
            .await
        }
    }))
    .await;

    let mut result = ConflictResult::default();
    for write in writes {
        match write {
            Ok(_) => result.successes += 1,
            Err(status) if status.code() == Code::Aborted => result.conflicts += 1,
            Err(status) if status.code() == Code::ResourceExhausted => result.exhausted += 1,
            Err(_) => result.unexpected += 1,
        }
    }
    let snapshot = api
        .get_project_snapshot(request(
            v1::GetProjectSnapshotRequest {
                project_id: project_id.to_string(),
            },
            admin_token,
        ))
        .await
        .expect("conflict snapshot should load")
        .into_inner();
    result.snapshot_revision = snapshot.revision;
    result.snapshot_tasks = snapshot.tasks.len();
    result
}

async fn collect_process_metrics(pool: PgPool, stop: CancellationToken) -> ProcessMetrics {
    let mut metrics = ProcessMetrics::default();
    let sampler_started = Instant::now();
    loop {
        let pid = std::process::id().to_string();
        if let Ok(Some((cpu_percent, rss_kb))) = tokio::task::spawn_blocking(move || {
            let output = Command::new("ps")
                .args(["-o", "%cpu=", "-o", "rss=", "-p", &pid])
                .output()
                .ok()?;
            let text = String::from_utf8(output.stdout).ok()?;
            let mut fields = text.split_whitespace();
            let cpu = fields.next()?.parse::<f64>().ok()?;
            let rss = fields.next()?.parse::<u64>().ok()?;
            Some((cpu, rss))
        })
        .await
        {
            if metrics.sample_count == 0 {
                metrics.rss_kb_start = rss_kb;
            }
            metrics.sample_count += 1;
            metrics.cpu_percent_sum += cpu_percent;
            metrics.cpu_percent_peak = metrics.cpu_percent_peak.max(cpu_percent);
            metrics.rss_kb_end = rss_kb;
            metrics.rss_kb_peak = metrics.rss_kb_peak.max(rss_kb);
            if sampler_started.elapsed() >= Duration::from_secs(300)
                && metrics.rss_kb_after_warmup.is_none()
            {
                metrics.rss_kb_after_warmup = Some(rss_kb);
            }
        }
        if let Ok((connections, lock_waiters)) = sqlx::query_as::<_, (i64, i64)>(
            r#"
            SELECT count(*)::bigint,
                   count(*) FILTER (WHERE wait_event_type = 'Lock')::bigint
            FROM pg_stat_activity
            WHERE datname = current_database()
            "#,
        )
        .fetch_one(&pool)
        .await
        {
            metrics.database_connections_peak = metrics.database_connections_peak.max(connections);
            metrics.database_lock_waiters_peak =
                metrics.database_lock_waiters_peak.max(lock_waiters);
        }

        tokio::select! {
            _ = stop.cancelled() => break,
            _ = tokio::time::sleep(Duration::from_secs(5)) => {}
        }
    }
    metrics
}

fn percentile(values: &[f64], percentile: f64) -> f64 {
    if values.is_empty() {
        return 0.0;
    }
    let index = ((values.len() - 1) as f64 * percentile)
        .round()
        .clamp(0.0, (values.len() - 1) as f64) as usize;
    values[index]
}

fn env_u64(name: &str, default: u64) -> u64 {
    std::env::var(name)
        .ok()
        .and_then(|value| value.parse::<u64>().ok())
        .unwrap_or(default)
}
