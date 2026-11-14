import Foundation
import XCTest
@testable import KshiftCore

final class RustFFIIntegrationTests: XCTestCase {
    func testRustClientReportsMissingConfigurationExplicitly() async {
        let client = RustClient(
            endpoint: nil,
            caPEM: nil,
            token: nil
        )
        do {
            _ = try await client.projects()
            XCTFail("Unconfigured RustClient must not return fabricated data.")
        } catch let error as KshiftClientError {
            guard case .ffiUnavailable = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRustClientReadsSnapshotWhenServerConfigurationIsProvided() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard
            let endpoint = environment["KSHIFT_ENDPOINT"],
            let caPath = environment["KSHIFT_CA_PATH"],
            !endpoint.isEmpty,
            !caPath.isEmpty
        else {
            throw XCTSkip("Set KSHIFT_ENDPOINT and KSHIFT_CA_PATH to run the live FFI test.")
        }

        let client = RustClient(
            endpoint: endpoint,
            caPEM: try Data(contentsOf: URL(fileURLWithPath: caPath)),
            token: environment["KSHIFT_TOKEN"]
        )
        let projects = try await client.projects()
        let first = try XCTUnwrap(projects.first)
        let snapshot = try await client.snapshot(projectID: first.id)
        XCTAssertEqual(snapshot.project.id, first.id)
    }
}
