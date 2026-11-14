import Foundation
import XCTest
@testable import Kshift

@MainActor
final class KshiftIOSTests: XCTestCase {
    func testAppBundleUsesKshiftIdentifier() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.wyz541.kshift.ios")
    }

    func testIOSLiveP0Scenario() async throws {
        guard KshiftIOSLiveP0Harness.isConfigured else {
            throw XCTSkip("Set live P0 E2E environment to run the iOS scenario.")
        }

        let report = try await KshiftIOSLiveP0Harness.run()
        XCTAssertEqual(report.platform, "iOS")
        XCTAssertEqual(report.primaryDate, "2026-11-15")
        XCTAssertEqual(report.secondaryDate, "2026-11-14")
        XCTAssertGreaterThan(report.stepCount, 20)
    }
}
