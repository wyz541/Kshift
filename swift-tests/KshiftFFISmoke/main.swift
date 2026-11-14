import Foundation

enum SmokeError: Error {
    case failed(String)
}

func argument(_ name: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: name),
          CommandLine.arguments.indices.contains(index + 1)
    else {
        return nil
    }
    return CommandLine.arguments[index + 1]
}

func main() throws {
    guard let endpoint = argument("--endpoint"),
          let caPath = argument("--ca")
    else {
        throw SmokeError.failed("usage: KshiftFFISmoke --endpoint URL --ca PATH")
    }
    let ca = try Data(contentsOf: URL(fileURLWithPath: caPath))
    let client = try KshiftClient(
        endpoint: endpoint,
        caPEM: ca,
        tlsDomain: "localhost",
        defaultDeadlineMilliseconds: 2_000
    )
    try client.updateToken("smoke-token")

    let projects = try client.listProjects()
    let projectJSON = try JSONSerialization.jsonObject(with: projects) as? [[String: Any]]
    guard projectJSON?.count == 1 else {
        throw SmokeError.failed("list_projects did not return one project")
    }

    let projectID = "11111111-2222-4333-8444-555555555555"
    let snapshot = try client.snapshot(projectID: projectID)
    guard String(data: snapshot, encoding: .utf8)?.contains("\"current_revision\":1") == true else {
        throw SmokeError.failed("snapshot JSON is missing revision 1")
    }

    let commandJSON = """
    {
      "client_id": "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
      "command_id": "99999999-8888-4777-8666-555555555555",
      "project_id": "\(projectID)",
      "expected_project_revision": 1,
      "command": {
        "type": "create_task",
        "value": {
          "title": "Swift smoke task",
          "description_markdown": "Created through the C ABI",
          "status": "todo",
          "priority": "medium",
          "assignee_ids": [],
          "planned_on": "2026-11-13",
          "due_on": "2026-11-20",
          "tags": ["smoke"],
          "dependency_task_ids": []
        }
      }
    }
    """
    let outcome = try client.executeCommand(Data(commandJSON.utf8))
    guard String(data: outcome, encoding: .utf8)?.contains("\"task_updated\"") == true else {
        throw SmokeError.failed("execute_command did not return a task event")
    }

    let planDepth = try client.planDepthSnapshot(projectID: projectID)
    guard
        let planSession = try JSONSerialization.jsonObject(with: planDepth) as? [String: Any],
        let planSnapshot = planSession["snapshot"] as? [String: Any],
        let planRevision = (planSnapshot["project"] as? [String: Any])?["revision"] as? NSNumber,
        let planTasks = planSnapshot["tasks"] as? [[String: Any]],
        let planTaskID = planTasks.first?["id"] as? String,
        let planVersion = planTasks.first?["version"] as? NSNumber
    else {
        throw SmokeError.failed("plan-depth snapshot JSON is incomplete")
    }
    let planCommandJSON = """
    {
      "request_id": "77777777-6666-4555-8444-333333333333",
      "project_id": "\(projectID)",
      "expected_revision": \(planRevision),
      "command": {
        "type": "set_task_status",
        "value": {
          "task_id": "\(planTaskID)",
          "status": "done",
          "expected_version": \(planVersion)
        }
      }
    }
    """
    let planUpdate = try client.executePlanDepthCommand(Data(planCommandJSON.utf8))
    guard
        let updateSession = try JSONSerialization.jsonObject(with: planUpdate) as? [String: Any],
        let updatedSnapshot = updateSession["snapshot"] as? [String: Any],
        let updatedProject = updatedSnapshot["project"] as? [String: Any],
        let updatedRevision = updatedProject["revision"] as? NSNumber
    else {
        throw SmokeError.failed("plan-depth command JSON is incomplete")
    }
    let planReport = try client.planDepthReport(
        projectID: projectID,
        startsOn: "2026-11-13",
        endsOn: "2026-11-14",
        today: "2026-11-14"
    )
    guard
        let report = try JSONSerialization.jsonObject(with: planReport) as? [String: Any],
        (report["source_revision"] as? NSNumber) == updatedRevision,
        (report["html"] as? String)?.contains("R3 smoke task") == true
    else {
        throw SmokeError.failed("plan-depth report does not match the updated revision")
    }

    let cancel = try KshiftCancelToken()
    let subscription = try client.watchProject(projectID: projectID, cancel: cancel)
    var sawSnapshot = false
    for _ in 0..<5 {
        let event = try subscription.next(timeoutMilliseconds: 2_000)
        guard let text = String(data: event, encoding: .utf8) else {
            throw SmokeError.failed("subscription event is not UTF-8")
        }
        if text.contains("\"kind\":\"snapshot\"") {
            sawSnapshot = true
            break
        }
    }
    guard sawSnapshot else {
        throw SmokeError.failed("subscription did not deliver a snapshot")
    }
    cancel.cancel()
    print("KSHIFT_SWIFT_FFI_SMOKE_OK projects=1 snapshot_bytes=\(snapshot.count) outcome_bytes=\(outcome.count) plan_depth_bytes=\(planDepth.count) plan_update_bytes=\(planUpdate.count) plan_report_bytes=\(planReport.count)")
}

do {
    try main()
} catch {
    fputs("KSHIFT_SWIFT_FFI_SMOKE_FAILED: \(error)\n", stderr)
    exit(1)
}
