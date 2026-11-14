import XCTest
@testable import KshiftCore

final class ModelEncodingTests: XCTestCase {
    func testCommandEncodingUsesCStableWireKeys() throws {
        let envelope = CommandEnvelope(
            requestID: "req-1",
            expectedRevision: 4,
            actorID: "person-mia",
            command: .setStatus(
                SetTasksStatusCommand(
                    items: [TaskVersionRef(taskID: "task-1", expectedTaskVersion: 2)],
                    status: .done
                )
            )
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(envelope)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"request_id\":\"req-1\""))
        XCTAssertTrue(json.contains("\"expected_revision\":4"))
        XCTAssertTrue(json.contains("\"kind\":\"set_tasks_status\""))
        XCTAssertTrue(json.contains("\"task_id\":\"task-1\""))
        XCTAssertTrue(json.contains("\"status\":\"done\""))
    }

    func testDateConversionRoundTripsWithoutTimezoneShift() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let date = try XCTUnwrap(KshiftDate.date(from: "2026-11-13", calendar: calendar))
        XCTAssertEqual(KshiftDate.isoString(from: date, calendar: calendar), "2026-11-13")
    }

    func testCreateTaskKeepsEveryAssignee() throws {
        let envelope = CommandEnvelope(
            requestID: "req-2",
            expectedRevision: 4,
            actorID: "person-mia",
            command: .create(
                CreateTaskCommand(
                    title: "Shared task",
                    notes: "",
                    status: .todo,
                    priority: .medium,
                    assigneeIDs: ["person-mia", "person-noah"],
                    dueDate: "2026-11-13"
                )
            )
        )
        let data = try JSONEncoder().encode(envelope)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\"assignee_ids\":[\"person-mia\",\"person-noah\"]"))
    }

    func testProjectDatesDoNotMoveWhenUserTimeZoneChanges() throws {
        var projectCalendar = Calendar(identifier: .gregorian)
        projectCalendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let projectDate = try XCTUnwrap(KshiftDate.date(from: "2026-11-13", calendar: projectCalendar))

        XCTAssertEqual(KshiftDate.isoString(from: projectDate, calendar: projectCalendar), "2026-11-13")
    }

    func testAbsoluteTimestampUsesUserTimeZoneForDisplay() {
        let utc = KshiftTime.formatTimestamp(
            "2026-11-13T16:30:00Z",
            timeZone: TimeZone(secondsFromGMT: 0)!,
            locale: Locale(identifier: "en_US_POSIX"),
            format: "yyyy-MM-dd HH:mm"
        )
        let shanghai = KshiftTime.formatTimestamp(
            "2026-11-13T16:30:00Z",
            timeZone: TimeZone(identifier: "Asia/Shanghai")!,
            locale: Locale(identifier: "en_US_POSIX"),
            format: "yyyy-MM-dd HH:mm"
        )

        XCTAssertEqual(utc, "2026-11-13 16:30")
        XCTAssertEqual(shanghai, "2026-11-14 00:30")
    }

    func testSnapshotMappingGroupsAuditHistoryByTask() throws {
        let json = """
        {
          "project": {
            "id": "project-1",
            "name": "Live Kshift",
            "current_revision": 3
          },
          "members": [
            {
              "user_id": "person-1",
              "display_name": "Mia Chen"
            }
          ],
          "tasks": [
            {
              "id": "task-1",
              "project_id": "project-1",
              "title": "Live history task",
              "description_markdown": "",
              "status": "done",
              "priority": "high",
              "assignee_ids": ["person-1"],
              "planned_on": "2026-11-13",
              "due_on": "2026-11-13",
              "version": 2,
              "updated_by": "person-1",
              "updated_at": "2026-11-13T02:00:02Z"
            }
          ],
          "audit": [
            {
              "id": "audit-1",
              "revision": 2,
              "action": "create_task",
              "summary": "创建任务 Live history task",
              "task_id": "task-1",
              "actor_id": "person-1",
              "occurred_at": "2026-11-13T02:00:01Z"
            },
            {
              "id": "audit-2",
              "revision": 3,
              "action": "update_task",
              "summary": "更新任务 Live history task",
              "task_id": "task-1",
              "actor_id": "person-1",
              "occurred_at": "2026-11-13T02:00:02Z"
            }
          ]
        }
        """

        let snapshot = try RustClient.decodeSnapshot(Data(json.utf8))
        let task = try XCTUnwrap(snapshot.tasks.first)

        XCTAssertEqual(snapshot.audit.count, 2)
        XCTAssertEqual(task.history.map(\.revision), [2, 3])
        XCTAssertEqual(
            task.history.map(\.summary),
            ["创建任务 Live history task", "更新任务 Live history task"]
        )
        XCTAssertEqual(task.history.first?.actorID, "person-1")
    }
}
