import XCTest
@testable import KshiftCore

final class KshiftClientFactoryTests: XCTestCase {
    func testConfiguredEndpointSelectsRustClientInDebugBuilds() {
        XCTAssertTrue(
            KshiftClientFactory.shouldUseRustClient(
                environment: ["KSHIFT_ENDPOINT": "https://kshift.internal"]
            )
        )
    }

    func testExplicitDemoModeOverridesConfiguredEndpoint() {
        XCTAssertFalse(
            KshiftClientFactory.shouldUseRustClient(
                environment: [
                    "KSHIFT_ENDPOINT": "https://kshift.internal",
                    "KSHIFT_DEMO_MODE": "1",
                ]
            )
        )
    }

    func testExplicitFFIModeOverridesDemoMode() {
        XCTAssertTrue(
            KshiftClientFactory.shouldUseRustClient(
                environment: [
                    "KSHIFT_USE_FFI": "1",
                    "KSHIFT_DEMO_MODE": "1",
                ]
            )
        )
    }

    func testEmptyEndpointDoesNotSelectRemoteClient() {
        XCTAssertFalse(
            KshiftClientFactory.shouldUseRustClient(
                environment: ["KSHIFT_ENDPOINT": ""]
            )
        )
    }
}
