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
}
