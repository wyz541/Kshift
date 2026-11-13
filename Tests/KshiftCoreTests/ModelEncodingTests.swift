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
}
