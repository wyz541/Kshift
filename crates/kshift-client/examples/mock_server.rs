use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

use chrono::{NaiveDate, TimeZone, Utc};
use contract::v1;
use domain::{
    Change, ChangeEvent, Command, Project, ProjectMember, ProjectRole, ProjectSnapshot, Task,
};
use tokio::sync::mpsc;
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

struct State {
    revision: AtomicU64,
    tasks: std::sync::Mutex<Vec<Task>>,
    plan_task_version: AtomicU64,
    plan_status: std::sync::Mutex<kshift_core::TaskStatus>,
}

#[derive(Clone)]
struct MockService {
    state: Arc<State>,
}

impl MockService {
    fn snapshot(&self) -> ProjectSnapshot {
        ProjectSnapshot {
            project: Project {
                id: project_id(),
                name: "Kshift smoke".to_owned(),
                time_zone: "Asia/Shanghai".to_owned(),
                current_revision: self.state.revision.load(Ordering::SeqCst),
                created_at: now(),
                updated_at: now(),
            },
            members: vec![ProjectMember {
                user_id: user_id(),
                display_name: "Smoke User".to_owned(),
                role: ProjectRole::Admin,
            }],
            tasks: self
                .state
                .tasks
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner())
                .clone(),
            audit: Vec::new(),
            generated_at: now(),
        }
    }

    fn plan_snapshot(&self) -> kshift_core::PlanDepthSnapshot {
        let snapshot = self.snapshot();
        kshift_core::PlanDepthSnapshot {
            project: kshift_core::PlanProject {
                id: snapshot.project.id.to_string(),
                name: snapshot.project.name,
                revision: snapshot.project.current_revision,
                schema_version: kshift_core::PLAN_SCHEMA_VERSION,
            },
            people: vec![kshift_core::Person {
                id: user_id().to_string(),
                name: "Smoke User".to_owned(),
                initials: "SU".to_owned(),
                color_hex: "#2F7CF6".to_owned(),
            }],
            tasks: vec![kshift_core::PlanTask {
                id: "e0000000-0000-4000-8000-000000000001".to_owned(),
                project_id: project_id().to_string(),
                parent_id: None,
                title: "R3 smoke task".to_owned(),
                description_markdown: "Typed FFI smoke".to_owned(),
                status: *self
                    .state
                    .plan_status
                    .lock()
                    .unwrap_or_else(|poisoned| poisoned.into_inner()),
                priority: kshift_core::TaskPriority::Medium,
                assignee_id: Some(user_id().to_string()),
                starts_on: NaiveDate::from_ymd_opt(2026, 11, 13).unwrap(),
                due_on: NaiveDate::from_ymd_opt(2026, 11, 14).unwrap(),
                estimate_minutes: 60,
                position: 0,
                version: self.state.plan_task_version.load(Ordering::SeqCst),
                completed_at: None,
            }],
            dependencies: Vec::new(),
            attachments: Vec::new(),
            attachment_links: Vec::new(),
            history: Vec::new(),
        }
    }
}

#[tonic::async_trait]
impl contract::KshiftService for MockService {
    async fn list_projects(
        &self,
        request: Request<v1::ListProjectsRequest>,
    ) -> Result<Response<v1::ListProjectsResponse>, Status> {
        authorize(&request)?;
        Ok(Response::new(v1::ListProjectsResponse {
            projects: vec![contract::project_to_proto(&self.snapshot().project)],
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
            &self.snapshot(),
        )))
    }

    async fn execute_command(
        &self,
        request: Request<v1::ExecuteCommandRequest>,
    ) -> Result<Response<v1::ExecuteCommandResponse>, Status> {
        authorize(&request)?;
        let request = request.into_inner();
        let parsed =
            contract::parse_execute_command(&request).map_err(|error| error.to_status())?;
        let task = match parsed.envelope.command {
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
            } => Task {
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
            Command::CreateProject { .. }
            | Command::AddProjectMember { .. }
            | Command::UpdateTask { .. }
            | Command::DeleteTask { .. }
            | Command::BatchUpdateTasks { .. } => {
                return Err(Status::invalid_argument(
                    "smoke server only accepts create_task",
                ));
            }
        };
        self.state
            .tasks
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .push(task.clone());
        let revision = self.state.revision.fetch_add(1, Ordering::SeqCst) + 1;
        let event = ChangeEvent {
            project_id: project_id(),
            revision,
            schema_version: domain::SCHEMA_VERSION,
            command_id: parsed.envelope.command_id,
            occurred_at: now(),
            changes: vec![Change::TaskCreated { task }],
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
            snapshot: Some(contract::plan_depth_snapshot_to_proto(
                &self.plan_snapshot(),
            )),
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
        let mut store = kshift_core::PlanDepthStore::new(self.plan_snapshot())
            .map_err(|error| Status::failed_precondition(error.to_string()))?;
        let response = store.execute(&kshift_core::PlanCommandEnvelope {
            request_id: input.request_id.to_string(),
            project_id: input.project_id,
            expected_revision: input.expected_revision,
            actor_id: user_id().to_string(),
            actor_role: kshift_core::PlanActorRole::Admin,
            command: input.command,
        });
        if let Some(error) = response.error {
            return Err(contract::plan_error_to_api(error).to_status());
        }
        let task = response
            .snapshot
            .tasks
            .first()
            .ok_or_else(|| Status::internal("R3 smoke task disappeared"))?;
        self.state
            .revision
            .store(response.snapshot.project.revision, Ordering::SeqCst);
        self.state
            .plan_task_version
            .store(task.version, Ordering::SeqCst);
        *self
            .state
            .plan_status
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner()) = task.status;
        Ok(Response::new(contract::plan_command_response_to_proto(
            &response,
            kshift_core::PlanActorRole::Admin,
        )))
    }

    #[allow(clippy::result_large_err)]
    async fn get_plan_depth_report(
        &self,
        request: Request<v1::GetPlanDepthReportRequest>,
    ) -> Result<Response<v1::GetPlanDepthReportResponse>, Status> {
        authorize(&request)?;
        let request = request.into_inner();
        let requested = Uuid::parse_str(&request.project_id)
            .map_err(|_| Status::invalid_argument("project_id must be a UUID"))?;
        if requested != project_id() {
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
        let report = kshift_core::PlanDepthStore::new(self.plan_snapshot())
            .and_then(|store| store.report(&range, today))
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
        let project = Uuid::parse_str(&request.project_id)
            .map_err(|_| Status::invalid_argument("project_id must be a UUID"))?;
        if project != project_id() {
            return Err(Status::not_found("project not found"));
        }
        let (tx, rx) = mpsc::channel(4);
        let state = self.state.clone();
        tokio::spawn(async move {
            loop {
                let heartbeat = v1::WatchProjectChangesResponse {
                    payload: Some(v1::watch_project_changes_response::Payload::Heartbeat(
                        v1::Heartbeat {
                            project_revision: state.revision.load(Ordering::SeqCst),
                            sent_at: Some(prost_types::Timestamp {
                                seconds: now().timestamp(),
                                nanos: 0,
                            }),
                        },
                    )),
                };
                if tx.send(Ok(heartbeat)).await.is_err() {
                    break;
                }
                tokio::time::sleep(std::time::Duration::from_secs(15)).await;
            }
        });
        Ok(Response::new(Box::pin(ReceiverStream::new(rx))))
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
        Err(Status::unauthenticated("missing smoke token"))
    }
}

fn arg_value(args: &[String], name: &str) -> Result<String, String> {
    let position = args
        .iter()
        .position(|value| value == name)
        .ok_or_else(|| format!("missing {name}"))?;
    args.get(position + 1)
        .cloned()
        .ok_or_else(|| format!("missing value for {name}"))
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = std::env::args().collect();
    let cert = PathBuf::from(arg_value(&args, "--cert")?);
    let key = PathBuf::from(arg_value(&args, "--key")?);
    let ready_file = PathBuf::from(arg_value(&args, "--ready-file")?);
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await?;
    let address = listener.local_addr()?;
    let state = Arc::new(State {
        revision: AtomicU64::new(1),
        tasks: std::sync::Mutex::new(Vec::new()),
        plan_task_version: AtomicU64::new(1),
        plan_status: std::sync::Mutex::new(kshift_core::TaskStatus::Todo),
    });
    let service = MockService { state };
    std::fs::write(
        &ready_file,
        format!("https://localhost:{}\n", address.port()),
    )?;
    println!(
        "KSHIFT_MOCK_SERVER_READY https://localhost:{}",
        address.port()
    );
    Server::builder()
        .tls_config(ServerTlsConfig::new().identity(Identity::from_pem(
            std::fs::read(cert)?,
            std::fs::read(key)?,
        )))?
        .add_service(contract::KshiftServiceServer::new(service))
        .serve_with_incoming_shutdown(TcpListenerStream::new(listener), async {
            let _ = tokio::signal::ctrl_c().await;
        })
        .await?;
    Ok(())
}
