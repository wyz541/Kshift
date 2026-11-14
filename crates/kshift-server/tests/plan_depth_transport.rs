mod common;

use std::collections::HashMap;

use common::{create_project, create_task, created_task, request, TestApi, TestDatabase};
use contract::{v1, KshiftService};
use uuid::Uuid;

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn plan_depth_transport_reads_writes_and_reports_the_same_revision() {
    let Some(db) = TestDatabase::create().await else {
        return;
    };
    let admin_id = Uuid::new_v4();
    db.seed_user(admin_id, "Plan Admin", true).await;
    let api = TestApi::create(
        db.pool.clone(),
        HashMap::from([(admin_id, "plan-admin-token".to_owned())]),
    );
    let project_id = Uuid::new_v4();

    api.api
        .execute_command(request(
            create_project(project_id, Uuid::new_v4(), "Plan Project"),
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
                    "Plan Task",
                    "R3 transport",
                    1,
                ),
                api.token(admin_id),
            ))
            .await
            .expect("task should be created")
            .into_inner(),
    );
    let task_id = Uuid::parse_str(&task.id).expect("task id should be a UUID");

    let snapshot = api
        .api
        .get_plan_depth_snapshot(request(
            v1::GetPlanDepthSnapshotRequest {
                project_id: project_id.to_string(),
            },
            api.token(admin_id),
        ))
        .await
        .expect("plan depth snapshot should load")
        .into_inner();
    assert_eq!(snapshot.actor_role, v1::PlanActorRole::Admin as i32);
    let snapshot = snapshot.snapshot.expect("snapshot should be present");
    assert_eq!(snapshot.project.as_ref().expect("project").revision, 2);
    assert_eq!(snapshot.tasks.len(), 1);

    let command = v1::ExecutePlanDepthCommandRequest {
        request_id: Uuid::new_v4().to_string(),
        project_id: project_id.to_string(),
        expected_revision: 2,
        command: Some(v1::PlanCommand {
            command: Some(v1::plan_command::Command::SetTaskStatus(
                v1::SetPlanTaskStatusCommand {
                    task_id: task_id.to_string(),
                    status: v1::TaskStatus::Done as i32,
                    expected_version: 1,
                },
            )),
        }),
    };
    let updated = api
        .api
        .execute_plan_depth_command(request(command.clone(), api.token(admin_id)))
        .await
        .expect("plan depth command should commit")
        .into_inner();
    let updated = updated
        .snapshot
        .expect("updated snapshot should be present");
    assert_eq!(updated.project.as_ref().expect("project").revision, 3);
    assert_eq!(updated.tasks[0].status, v1::TaskStatus::Done as i32);
    assert_eq!(updated.tasks[0].version, 2);

    let retried = api
        .api
        .execute_plan_depth_command(request(command, api.token(admin_id)))
        .await
        .expect("plan depth retry should replay")
        .into_inner();
    let retried = retried
        .snapshot
        .expect("retried snapshot should be present");
    assert_eq!(retried.project.as_ref().expect("project").revision, 3);
    assert_eq!(retried.tasks[0].version, 2);

    let report = api
        .api
        .get_plan_depth_report(request(
            v1::GetPlanDepthReportRequest {
                project_id: project_id.to_string(),
                starts_on: "2026-11-01".to_owned(),
                ends_on: "2026-11-30".to_owned(),
                today: "2026-11-14".to_owned(),
            },
            api.token(admin_id),
        ))
        .await
        .expect("R3 report should load")
        .into_inner()
        .report
        .expect("report should be present");
    assert_eq!(report.source_revision, 3);
    assert_eq!(report.tasks.len(), 1);
    assert_eq!(report.tasks[0].status, v1::TaskStatus::Done as i32);

    db.cleanup().await;
}
