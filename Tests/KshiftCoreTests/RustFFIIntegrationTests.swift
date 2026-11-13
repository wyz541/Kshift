import Foundation
import XCTest
@testable import KshiftCore

final class RustFFIIntegrationTests: XCTestCase {
    func testRustClientReadsSnapshotThroughDynamicFFI() async throws {
        let path = FileManager.default.currentDirectoryPath
            + "/.build/ffi/macos/libkshift_ffi.dylib"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("Run scripts/build-ffi.sh macos before this test.")
        }

        let client = RustClient()
        let projects = try await client.projects()
        let first = try XCTUnwrap(projects.first)
        let snapshot = try await client.snapshot(projectID: first.id)
        XCTAssertEqual(snapshot.project.id, first.id)
        XCTAssertFalse(snapshot.tasks.isEmpty)
    }

    func testRustClientCreatesTaskThroughDynamicFFI() async throws {
        let path = FileManager.default.currentDirectoryPath
            + "/.build/ffi/macos/libkshift_ffi.dylib"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("Run scripts/build-ffi.sh macos before this test.")
        }

        let client = RustClient()
        let projects = try await client.projects()
        let project = try XCTUnwrap(projects.first)
        let before = try await client.snapshot(projectID: project.id)
        let title = "FFI create \(UUID().uuidString.prefix(8))"
        let response = try await client.execute(
            projectID: project.id,
            envelope: CommandEnvelope(
                expectedRevision: before.project.revision,
                actorID: client.actorID,
                command: .create(
                    CreateTaskCommand(
                        title: title,
                        notes: "Created through kshift-ffi",
                        status: .todo,
                        priority: .medium,
                        assigneeID: "person-mia",
                        dueDate: KshiftDate.isoString(from: .now)
                    )
                )
            )
        )

        XCTAssertTrue(response.ok)
        XCTAssertTrue(response.snapshot?.tasks.contains(where: { $0.title == title }) == true)
    }

}
