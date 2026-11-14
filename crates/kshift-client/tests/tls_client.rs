use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use chrono::{NaiveDate, TimeZone, Utc};
use contract::v1;
use domain::{
    Change, ChangeEvent, Command, Project, ProjectMember, ProjectRole, ProjectSnapshot, Task,
    TaskPriority, TaskStatus,
};
use kshift_client::{AuthToken, ClientConfig, ClientError, ClientEvent, KshiftClient};
use kshift_core::{PlanActorRole, PlanCommand, PlanCommandEnvelope};
use tokio::sync::{mpsc, oneshot};
use tokio_stream::wrappers::{ReceiverStream, TcpListenerStream};
use tonic::transport::{Identity, Server, ServerTlsConfig};
use tonic::{Request, Response, Status};
use uuid::Uuid;

const TOKEN: &str = "smoke-token";

fn project_id() -> Uuid {
    Uuid::from_u128(0x11111111_2222_4333_8444_555555555555)
}

fn user_id() -> Uuid {
    Uuid::from_u128(0xaaaaaaaa_bbbb_4ccc_8ddd_eeeeeeeeeeee)
}

fn now() -> chrono::DateTime<Utc> {
    Utc.with_ymd_and_hms(2026, 11, 13, 0, 0, 0)
        .single()
        .expect("valid timestamp")
}

fn task(version: u64) -> Task {
    Task {
        id: Uuid::from_u128(0x99999999_8888_4777_8666_555555555555),
        project_id: project_id(),
        title: "Ship client".to_owned(),
        description_markdown: "TLS integration".to_owned(),
        status: TaskStatus::InProgress,
        priority: TaskPriority::High,
        assignee_ids: vec![user_id()],
        planned_on: NaiveDate::from_ymd_opt(2026, 11, 13).unwrap(),
        starts_on: None,
        due_on: Some(NaiveDate::from_ymd_opt(2026, 11, 20).unwrap()),
        tags: vec!["tls".to_owned()],
        parent_task_id: None,
        dependency_task_ids: Vec::new(),
        version,
        created_by: user_id(),
        updated_by: user_id(),
        created_at: now(),
        updated_at: now(),
    }
}

fn snapshot(revision: u64) -> ProjectSnapshot {
    ProjectSnapshot {
        project: Project {
            id: project_id(),
            name: "Kshift".to_owned(),
            time_zone: "Asia/Shanghai".to_owned(),
            current_revision: revision,
            created_at: now(),
            updated_at: now(),
        },
        members: vec![ProjectMember {
            user_id: user_id(),
            display_name: "Test User".to_owned(),
            role: ProjectRole::Admin,
        }],
        tasks: vec![task(1)],
        audit: Vec::new(),
        generated_at: now(),
    }
}

fn plan_snapshot() -> kshift_core::PlanDepthSnapshot {
    let mut snapshot = kshift_core::demo_snapshot(NaiveDate::from_ymd_opt(2026, 11, 13).unwrap());
    snapshot.project.id = project_id().to_string();
    let task_ids = snapshot
        .tasks
        .iter()
        .enumerate()
        .map(|(index, task)| {
            (
                task.id.clone(),
                Uuid::from_u128(0xe0000000_0000_4000_8000_000000000000_u128 + index as u128)
                    .to_string(),
            )
        })
        .collect::<HashMap<_, _>>();
    for task in &mut snapshot.tasks {
        task.project_id = project_id().to_string();
        if let Some(id) = task_ids.get(&task.id) {
            task.id = id.clone();
        }
        task.parent_id = task
            .parent_id
            .as_ref()
            .and_then(|id| task_ids.get(id).cloned());
    }
    for dependency in &mut snapshot.dependencies {
        if let Some(id) = task_ids.get(&dependency.task_id) {
            dependency.task_id = id.clone();
        }
        if let Some(id) = task_ids.get(&dependency.depends_on_task_id) {
            dependency.depends_on_task_id = id.clone();
        }
    }
    let attachment_ids = snapshot
        .attachments
        .iter()
        .enumerate()
        .map(|(index, attachment)| {
            (
                attachment.id.clone(),
                Uuid::from_u128(0xf0000000_0000_4000_8000_000000000000_u128 + index as u128)
                    .to_string(),
            )
        })
        .collect::<HashMap<_, _>>();
    for attachment in &mut snapshot.attachments {
        if let Some(id) = attachment_ids.get(&attachment.id) {
            attachment.id = id.clone();
        }
    }
    for link in &mut snapshot.attachment_links {
        if let Some(id) = attachment_ids.get(&link.attachment_id) {
            link.attachment_id = id.clone();
        }
        if let Some(id) = task_ids.get(&link.task_id) {
            link.task_id = id.clone();
        }
    }
    for (index, entry) in snapshot.history.iter_mut().enumerate() {
        entry.id = Uuid::from_u128(0xa0000000_0000_4000_8000_000000000000_u128 + index as u128)
            .to_string();
    }
    snapshot
}

struct MockState {
    snapshot_revision: u64,
    execute_calls: AtomicUsize,
    fail_first_execute: AtomicBool,
    execute_delay: Mutex<Duration>,
    watch_calls: AtomicUsize,
}

impl Default for MockState {
    fn default() -> Self {
        Self {
            snapshot_revision: 5,
            execute_calls: AtomicUsize::new(0),
            fail_first_execute: AtomicBool::new(false),
            execute_delay: Mutex::new(Duration::ZERO),
            watch_calls: AtomicUsize::new(0),
        }
    }
}

#[derive(Clone)]
struct MockService {
    state: Arc<MockState>,
}

#[tonic::async_trait]
impl contract::KshiftService for MockService {
    async fn list_projects(
        &self,
        request: Request<v1::ListProjectsRequest>,
    ) -> Result<Response<v1::ListProjectsResponse>, Status> {
        authorize(&request)?;
        Ok(Response::new(v1::ListProjectsResponse {
            projects: vec![contract::project_to_proto(
                &snapshot(self.state.snapshot_revision).project,
            )],
        }))
    }

    async fn get_project_snapshot(
        &self,
        request: Request<v1::GetProjectSnapshotRequest>,
    ) -> Result<Response<v1::GetProjectSnapshotResponse>, Status> {
        authorize(&request)?;
        let requested = Uuid::parse_str(&request.into_inner().project_id)
            .map_err(|_| Status::invalid_argument("project_id must be a UUID"))?;
        if requested != project_id() {
            return Err(Status::not_found("project not found"));
        }
        Ok(Response::new(contract::project_snapshot_to_proto(
            &snapshot(self.state.snapshot_revision),
        )))
    }

    async fn execute_command(
        &self,
        request: Request<v1::ExecuteCommandRequest>,
    ) -> Result<Response<v1::ExecuteCommandResponse>, Status> {
        authorize(&request)?;
        let call = self.state.execute_calls.fetch_add(1, Ordering::SeqCst);
        let delay = *self
            .state
            .execute_delay
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        if !delay.is_zero() {
            tokio::time::sleep(delay).await;
        }
        if self.state.fail_first_execute.load(Ordering::SeqCst) && call == 0 {
            return Err(Status::unavailable("retry once"));
        }
        let request = request.into_inner();
        let parsed =
            contract::parse_execute_command(&request).map_err(|error| error.to_status())?;
        let revision = self.state.snapshot_revision + 1;
        let event = match parsed.envelope.command {
            Command::CreateTask {
                task_id,
                title,
                description_markdown,
                status,
                priority,
                assignee_ids,
                planned_on,
                starts_on,
                due_on,
                tags,
                parent_task_id,
                dependency_task_ids,
            } => ChangeEvent {
                project_id: project_id(),
                revision,
                schema_version: domain::SCHEMA_VERSION,
                command_id: parsed.envelope.command_id,
                occurred_at: now(),
                changes: vec![Change::TaskCreated {
                    task: Task {
                        id: task_id,
                        project_id: project_id(),
                        title,
                        description_markdown,
                        status,
                        priority,
                        assignee_ids,
                        planned_on,
                        starts_on,
                        due_on,
                        tags,
                        parent_task_id,
                        dependency_task_ids,
                        version: 1,
                        created_by: user_id(),
                        updated_by: user_id(),
                        created_at: now(),
                        updated_at: now(),
                    },
                }],
            },
            Command::UpdateTask { task_id, .. } => ChangeEvent {
                project_id: project_id(),
                revision,
                schema_version: domain::SCHEMA_VERSION,
                command_id: parsed.envelope.command_id,
                occurred_at: now(),
                changes: vec![Change::TaskUpdated {
                    task: Task {
                        id: task_id,
                        version: 2,
                        ..task(1)
                    },
                }],
            },
            Command::DeleteTask { task_id, .. } => ChangeEvent {
                project_id: project_id(),
                revision,
                schema_version: domain::SCHEMA_VERSION,
                command_id: parsed.envelope.command_id,
                occurred_at: now(),
                changes: vec![Change::TaskDeleted { task_id }],
            },
            Command::CreateProject { .. }
            | Command::AddProjectMember { .. }
            | Command::BatchUpdateTasks { .. } => {
                return Err(Status::invalid_argument("unexpected command in test"));
            }
        };
        Ok(Response::new(v1::ExecuteCommandResponse {
            result: Some(v1::CommandResult {
                command_id: parsed.envelope.command_id.to_string(),
                project_revision: revision,
                event: Some(contract::change_event_to_proto(&event)),
            }),
        }))
    }

    async fn get_plan_depth_snapshot(
        &self,
        request: Request<v1::GetPlanDepthSnapshotRequest>,
    ) -> Result<Response<v1::GetPlanDepthSnapshotResponse>, Status> {
        authorize(&request)?;
        let requested = Uuid::parse_str(&request.into_inner().project_id)
            .map_err(|_| Status::invalid_argument("project_id must be a UUID"))?;
        if requested != project_id() {
            return Err(Status::not_found("project not found"));
        }
        Ok(Response::new(v1::GetPlanDepthSnapshotResponse {
            snapshot: Some(contract::plan_depth_snapshot_to_proto(&plan_snapshot())),
            actor_role: v1::PlanActorRole::Admin as i32,
        }))
    }

    async fn execute_plan_depth_command(
        &self,
        request: Request<v1::ExecutePlanDepthCommandRequest>,
    ) -> Result<Response<v1::ExecutePlanDepthCommandResponse>, Status> {
        authorize(&request)?;
        let input = contract::parse_execute_plan_depth_command(request.get_ref())
            .map_err(|error| error.to_status())?;
        let mut store = kshift_core::PlanDepthStore::new(plan_snapshot())
            .map_err(|error| Status::failed_precondition(error.to_string()))?;
        let envelope = PlanCommandEnvelope {
            request_id: input.request_id.to_string(),
            project_id: input.project_id,
            expected_revision: input.expected_revision,
            actor_id: "d0000000-0000-4000-8000-000000000002".to_owned(),
            actor_role: PlanActorRole::Admin,
            command: input.command,
        };
        let response = store.execute(&envelope);
        if let Some(error) = response.error {
            return Err(contract::plan_error_to_api(error).to_status());
        }
        Ok(Response::new(contract::plan_command_response_to_proto(
            &response,
            PlanActorRole::Admin,
        )))
    }

    #[allow(clippy::result_large_err)]
    async fn get_plan_depth_report(
        &self,
        request: Request<v1::GetPlanDepthReportRequest>,
    ) -> Result<Response<v1::GetPlanDepthReportResponse>, Status> {
        authorize(&request)?;
        let request = request.into_inner();
        let project = Uuid::parse_str(&request.project_id)
            .map_err(|_| Status::invalid_argument("project_id must be a UUID"))?;
        if project != project_id() {
            return Err(Status::not_found("project not found"));
        }
        let parse = |value: &str, field: &str| {
            NaiveDate::parse_from_str(value, "%Y-%m-%d")
                .map_err(|_| Status::invalid_argument(format!("{field} must use YYYY-MM-DD")))
        };
        let range = kshift_core::ReportRange {
            starts_on: parse(&request.starts_on, "starts_on")?,
            ends_on: parse(&request.ends_on, "ends_on")?,
        };
        let today = parse(&request.today, "today")?;
        let store = kshift_core::PlanDepthStore::new(plan_snapshot())
            .map_err(|error| Status::failed_precondition(error.to_string()))?;
        let report = store
            .report(&range, today)
            .map_err(|error| Status::failed_precondition(error.to_string()))?;
        Ok(Response::new(v1::GetPlanDepthReportResponse {
            report: Some(contract::plan_report_to_proto(&report)),
        }))
    }

    type WatchProjectChangesStream = std::pin::Pin<
        Box<
            dyn futures_util::Stream<Item = Result<v1::WatchProjectChangesResponse, Status>> + Send,
        >,
    >;

    async fn watch_project_changes(
        &self,
        request: Request<v1::WatchProjectChangesRequest>,
    ) -> Result<Response<Self::WatchProjectChangesStream>, Status> {
        authorize(&request)?;
        let request = request.into_inner();
        let call = self.state.watch_calls.fetch_add(1, Ordering::SeqCst);
        let (tx, rx) = mpsc::channel(4);
        let project = Uuid::parse_str(&request.project_id)
            .map_err(|_| Status::invalid_argument("project_id must be a UUID"))?;
        if project != project_id() {
            return Err(Status::not_found("project not found"));
        }
        let event = if call == 0 {
            change_event(7, Change::TaskUpdated { task: task(2) })
        } else {
            change_event(6, Change::TaskUpdated { task: task(2) })
        };
        tx.send(Ok(v1::WatchProjectChangesResponse {
            payload: Some(v1::watch_project_changes_response::Payload::Event(
                contract::change_event_to_proto(&event),
            )),
        }))
        .await
        .map_err(|_| Status::internal("watch send failed"))?;
        if call > 0 {
            let _ = tx
                .send(Ok(v1::WatchProjectChangesResponse {
                    payload: Some(v1::watch_project_changes_response::Payload::Heartbeat(
                        v1::Heartbeat {
                            project_revision: self.state.snapshot_revision,
                            sent_at: Some(timestamp(now())),
                        },
                    )),
                }))
                .await;
        }
        Ok(Response::new(Box::pin(ReceiverStream::new(rx))))
    }
}

fn change_event(revision: u64, change: Change) -> ChangeEvent {
    ChangeEvent {
        project_id: project_id(),
        revision,
        schema_version: domain::SCHEMA_VERSION,
        command_id: Uuid::new_v4(),
        occurred_at: now(),
        changes: vec![change],
    }
}

fn timestamp(value: chrono::DateTime<Utc>) -> prost_types::Timestamp {
    prost_types::Timestamp {
        seconds: value.timestamp(),
        nanos: value.timestamp_subsec_nanos() as i32,
    }
}

#[allow(clippy::result_large_err)]
fn authorize<T>(request: &Request<T>) -> Result<(), Status> {
    let expected = format!("Bearer {TOKEN}");
    if request
        .metadata()
        .get("authorization")
        .and_then(|value| value.to_str().ok())
        == Some(expected.as_str())
    {
        Ok(())
    } else {
        Err(Status::unauthenticated("missing test token"))
    }
}

async fn start_server(
    state: Arc<MockState>,
) -> (String, oneshot::Sender<()>, tokio::task::JoinHandle<()>) {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind test server");
    let address = listener.local_addr().expect("local address");
    let identity = Identity::from_pem(
        include_bytes!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../fixtures/tls/server.pem"
        )),
        include_bytes!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../fixtures/tls/server-key.pem"
        )),
    );
    let (shutdown_tx, shutdown_rx) = oneshot::channel();
    let service = MockService { state };
    let handle = tokio::spawn(async move {
        Server::builder()
            .tls_config(ServerTlsConfig::new().identity(identity))
            .expect("server TLS")
            .add_service(contract::KshiftServiceServer::new(service))
            .serve_with_incoming_shutdown(TcpListenerStream::new(listener), async {
                let _ = shutdown_rx.await;
            })
            .await
            .expect("server task");
    });
    tokio::time::sleep(Duration::from_millis(50)).await;
    (
        format!("https://localhost:{}", address.port()),
        shutdown_tx,
        handle,
    )
}

fn client(endpoint: &str) -> KshiftClient {
    let config = ClientConfig::new(
        endpoint,
        include_bytes!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../fixtures/tls/ca.pem"
        ))
        .to_vec(),
        Some("localhost".to_owned()),
        Duration::from_secs(2),
        16 * 1024 * 1024,
    )
    .expect("client config");
    KshiftClient::new(config).expect("client")
}

fn create_task_command(title: &str) -> domain::CommandEnvelope {
    domain::CommandEnvelope {
        client_id: Uuid::new_v4(),
        command_id: Uuid::new_v4(),
        project_id: project_id(),
        expected_revision: Some(5),
        command: Command::CreateTask {
            task_id: Uuid::new_v4(),
            title: title.to_owned(),
            description_markdown: String::new(),
            status: TaskStatus::Todo,
            priority: TaskPriority::Medium,
            assignee_ids: Vec::new(),
            planned_on: NaiveDate::from_ymd_opt(2026, 11, 13).unwrap(),
            starts_on: None,
            due_on: None,
            tags: Vec::new(),
            parent_task_id: None,
            dependency_task_ids: Vec::new(),
        },
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tls_snapshot_and_retry_work() {
    let state = Arc::new(MockState::default());
    state.fail_first_execute.store(true, Ordering::SeqCst);
    let (endpoint, shutdown, server) = start_server(state.clone()).await;
    let client = client(&endpoint);
    client.set_token(AuthToken::new(TOKEN).unwrap()).await;
    let cancel = tokio_util::sync::CancellationToken::new();

    let projects = client
        .list_projects(None, &cancel)
        .await
        .expect("list projects");
    assert_eq!(projects.len(), 1);
    assert_eq!(projects[0].id, project_id());

    let snapshot = client
        .get_snapshot(project_id(), None, &cancel)
        .await
        .expect("snapshot");
    assert_eq!(snapshot.project.current_revision, 5);

    let command = create_task_command("New task");
    let outcome = client
        .execute_command(&command, None, &cancel)
        .await
        .expect("command outcome");
    assert_eq!(outcome.revision, 6);
    assert_eq!(outcome.command_id, command.command_id);
    assert_eq!(state.execute_calls.load(Ordering::SeqCst), 2);
    assert!(outcome
        .event
        .changes
        .iter()
        .any(|change| matches!(change, Change::TaskUpdated { .. })));

    let _ = shutdown.send(());
    server.await.expect("server shutdown");
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn plan_depth_snapshot_command_and_report_use_typed_grpc() {
    let state = Arc::new(MockState::default());
    let (endpoint, shutdown, server) = start_server(state).await;
    let client = client(&endpoint);
    client.set_token(AuthToken::new(TOKEN).unwrap()).await;
    let cancel = tokio_util::sync::CancellationToken::new();

    let session = client
        .get_plan_depth_snapshot(project_id(), None, &cancel)
        .await
        .expect("plan depth snapshot");
    assert_eq!(session.actor_role, PlanActorRole::Admin);
    assert_eq!(session.snapshot.project.revision, 7);
    let task = session
        .snapshot
        .tasks
        .first()
        .expect("demo task should exist")
        .clone();

    let input = contract::PlanDepthCommandInput {
        request_id: Uuid::new_v4(),
        project_id: project_id(),
        expected_revision: 7,
        command: PlanCommand::SetTaskStatus {
            task_id: task.id,
            status: kshift_core::TaskStatus::Done,
            expected_version: task.version,
        },
    };
    let updated = client
        .execute_plan_depth_command(&input, None, &cancel)
        .await
        .expect("plan depth command");
    assert_eq!(updated.snapshot.project.revision, 8);
    assert_eq!(
        updated.snapshot.tasks[0].status,
        kshift_core::TaskStatus::Done
    );

    let report = client
        .get_plan_depth_report(
            project_id(),
            &kshift_core::ReportRange {
                starts_on: NaiveDate::from_ymd_opt(2026, 11, 1).unwrap(),
                ends_on: NaiveDate::from_ymd_opt(2026, 11, 30).unwrap(),
            },
            NaiveDate::from_ymd_opt(2026, 11, 13).unwrap(),
            None,
            &cancel,
        )
        .await
        .expect("plan depth report");
    assert_eq!(report.source_revision, 7);
    assert!(!report.tasks.is_empty());

    let _ = shutdown.send(());
    server.await.expect("server shutdown");
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn cancellation_and_deadline_are_typed() {
    let state = Arc::new(MockState::default());
    *state
        .execute_delay
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner()) = Duration::from_secs(2);
    let (endpoint, shutdown, server) = start_server(state).await;
    let client = client(&endpoint);
    client.set_token(AuthToken::new(TOKEN).unwrap()).await;
    let command = create_task_command("Slow");
    let cancel = tokio_util::sync::CancellationToken::new();
    let cancel_task = tokio::spawn({
        let cancel = cancel.clone();
        async move {
            tokio::time::sleep(Duration::from_millis(50)).await;
            cancel.cancel();
        }
    });
    let error = client
        .execute_command(&command, Some(Duration::from_secs(3)), &cancel)
        .await
        .expect_err("command should cancel");
    assert!(matches!(error, ClientError::Cancelled));
    cancel_task.await.unwrap();

    let deadline_error = client
        .execute_command(
            &command,
            Some(Duration::from_millis(100)),
            &tokio_util::sync::CancellationToken::new(),
        )
        .await
        .expect_err("command should time out");
    assert!(
        matches!(deadline_error, ClientError::DeadlineExceeded),
        "unexpected error: {deadline_error:?}"
    );

    let _ = shutdown.send(());
    server.await.expect("server shutdown");
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn revision_gap_resets_and_refetches_snapshot() {
    let state = Arc::new(MockState::default());
    let (endpoint, shutdown, server) = start_server(state.clone()).await;
    let client = client(&endpoint);
    client.set_token(AuthToken::new(TOKEN).unwrap()).await;
    let cancel = tokio_util::sync::CancellationToken::new();
    let (tx, mut rx) = mpsc::channel(16);
    let watch = tokio::spawn({
        let cancel = cancel.clone();
        async move { client.watch_project(project_id(), None, cancel, tx).await }
    });

    let first = tokio::time::timeout(Duration::from_secs(3), rx.recv())
        .await
        .unwrap()
        .unwrap();
    assert!(
        matches!(first, ClientEvent::Snapshot(ref value) if value.project.current_revision == 5)
    );
    let reset = tokio::time::timeout(Duration::from_secs(3), rx.recv())
        .await
        .unwrap()
        .unwrap();
    assert!(matches!(reset, ClientEvent::ResetRequired(_)));
    let mut saw_snapshot = false;
    let mut saw_change = false;
    for _ in 0..6 {
        let event = tokio::time::timeout(Duration::from_secs(3), rx.recv())
            .await
            .unwrap()
            .expect("watch event");
        match event {
            ClientEvent::Snapshot(value) => {
                assert_eq!(value.project.current_revision, 5);
                saw_snapshot = true;
            }
            ClientEvent::Change(value) => {
                assert_eq!(value.revision, 6);
                saw_change = true;
                break;
            }
            ClientEvent::Reconnecting(_) => {}
            other => panic!("unexpected event: {other:?}"),
        }
    }
    assert!(saw_snapshot && saw_change);
    assert!(state.watch_calls.load(Ordering::SeqCst) >= 2);
    cancel.cancel();
    let _ = tokio::time::timeout(Duration::from_secs(2), watch).await;
    let _ = shutdown.send(());
    server.await.expect("server shutdown");
}
