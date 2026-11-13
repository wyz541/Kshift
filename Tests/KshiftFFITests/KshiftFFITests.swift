import Foundation
import XCTest
@testable import KshiftFFI

final class KshiftFFITests: XCTestCase {
    func testCreateInvalidCommandAndDestroy() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let ca = try Data(contentsOf: root.appendingPathComponent("fixtures/tls/ca.pem"))
        let client = try KshiftClient(
            endpoint: "https://localhost:65535",
            caPEM: ca,
            tlsDomain: "localhost",
            defaultDeadlineMilliseconds: 100
        )
        XCTAssertThrowsError(try client.executeCommand(Data("{not-json}".utf8))) { error in
            let error = error as? KshiftCFFIError
            XCTAssertEqual(error?.code, "invalid_argument")
        }
    }

    func testCancelTokenLifecycle() throws {
        let token = try KshiftCancelToken()
        token.cancel()
    }
}
