import Foundation
import KshiftAppKitAdapter
import KshiftPresentation
import XCTest
@testable import KshiftCore
@testable import KshiftUI

@MainActor
final class LiveP0E2ETests: XCTestCase {
    func testDefaultClientsShareRemoteWrites() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let expectations = KshiftP0E2EExpectations.fromEnvironment(environment) else {
            throw XCTSkip("Set live P0 E2E environment to run the shared-write scenario.")
        }
        var configuration = environment
        configuration.removeValue(forKey: "KSHIFT_USE_FFI")
        configuration.removeValue(forKey: "KSHIFT_DEMO_MODE")
        let writer = KshiftClientFactory.makeDefault(environment: configuration)
        let reader = KshiftClientFactory.makeDefault(environment: configuration)
        XCTAssertTrue(writer is RustClient)
        XCTAssertTrue(reader is RustClient)

        let projects = try await reader.projects()
        let project = try XCTUnwrap(projects.first { $0.name == expectations.primaryProjectName })
        let before = try await reader.snapshot(projectID: project.id)
        let title = "Remote persistence probe \(UUID())"
        let created = try await writer.execute(
            projectID: project.id,
            envelope: CommandEnvelope(
                expectedRevision: before.project.revision,
                actorID: writer.actorID,
                command: .create(CreateTaskCommand(
                    title: title,
                    notes: "",
                    status: .todo,
                    priority: .medium,
                    assigneeIDs: [],
                    dueDate: expectations.primaryDate
                ))
            )
        )
        XCTAssertTrue(created.ok, "Expected the server to accept the create command.")
        let after = try await reader.snapshot(projectID: project.id)
        XCTAssertEqual(after.project.revision, before.project.revision + 1)
        let task = try XCTUnwrap(after.tasks.first { $0.title == title })

        let deleted = try await writer.execute(
            projectID: project.id,
            envelope: CommandEnvelope(
                expectedRevision: after.project.revision,
                actorID: writer.actorID,
                command: .delete(taskID: task.id, expectedTaskVersion: task.version)
            )
        )
        XCTAssertTrue(deleted.ok, "Expected the server to accept the delete command.")
        let final = try await reader.snapshot(projectID: project.id)
        XCTAssertEqual(final.project.revision, after.project.revision + 1)
        XCTAssertFalse(final.tasks.contains { $0.id == task.id })
    }

    func testMacOSLiveP0Scenario() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let endpoint = environment["KSHIFT_ENDPOINT"],
              let token = environment["KSHIFT_TOKEN"],
              let actorID = environment["KSHIFT_ACTOR_ID"],
              let expectations = KshiftP0E2EExpectations.fromEnvironment(environment)
        else {
            throw XCTSkip("Set live P0 E2E environment to run the macOS scenario.")
        }
        let caPEM: Data
        if let value = environment["KSHIFT_CA_PEM"] {
            caPEM = Data(value.utf8)
        } else if let caPath = environment["KSHIFT_CA_PATH"] {
            caPEM = try Data(contentsOf: URL(fileURLWithPath: caPath))
        } else {
            throw XCTSkip("Set KSHIFT_CA_PEM or KSHIFT_CA_PATH.")
        }

        let client = RustClient(
            actorID: actorID,
            endpoint: endpoint,
            caPEM: caPEM,
            token: token,
            deadlineMilliseconds: 15_000
        )
        let userTimeZone = TimeZone(
            identifier: environment["KSHIFT_USER_TIME_ZONE"] ?? ""
        ) ?? TimeZone(identifier: "America/Los_Angeles")!
        let now = parseTimestamp(environment["KSHIFT_NOW"]) ?? Date()
        let model = AppModel(
            client: client,
            platform: AppKitPlatformCapabilities(),
            userTimeZone: userTimeZone,
            now: { now }
        )

        let report = try await KshiftP0E2EProbe.run(
            model: model,
            platform: .macOS,
            expectations: expectations
        )
        XCTAssertEqual(report.platform, "macOS")
        XCTAssertEqual(report.primaryDate, expectations.primaryDate)
        XCTAssertGreaterThan(report.steps.count, 20)

        if let reportPath = environment["KSHIFT_P0_E2E_REPORT"] {
            let data = try JSONEncoder().encode(report)
            try data.write(to: URL(fileURLWithPath: reportPath), options: .atomic)
        }
    }

    private func parseTimestamp(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
