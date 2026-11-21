import XCTest
@testable import KshiftCore

final class KshiftClientFactoryTests: XCTestCase {
    func testMissingConfigurationDoesNotFallBackToDemo() async {
        await assertSetupError(environment: [:], contains: "KSHIFT_ENDPOINT")
        await assertSetupError(environment: ["KSHIFT_ENDPOINT": ""], contains: "KSHIFT_ENDPOINT")
    }

    func testExplicitDemoModeOverridesConfiguredEndpoint() {
        let client = KshiftClientFactory.makeDefault(environment: [
            "KSHIFT_ENDPOINT": "https://kshift.internal",
            "KSHIFT_DEMO_MODE": "1",
        ])
        XCTAssertTrue(client is DemoKshiftClient)
    }

    func testExplicitFFIModeOverridesDemoMode() {
        let client = KshiftClientFactory.makeDefault(environment: [
            "KSHIFT_USE_FFI": "1",
            "KSHIFT_DEMO_MODE": "1",
        ])
        XCTAssertTrue(client is RustClient)
    }

    func testInjectedEndpointReachesRustClient() async {
        await assertSetupError(
            environment: ["KSHIFT_ENDPOINT": "https://kshift.internal"],
            contains: "KSHIFT_CA_PATH"
        )
    }

    private func assertSetupError(
        environment: [String: String],
        contains key: String
    ) async {
        let client = KshiftClientFactory.makeDefault(environment: environment)
        XCTAssertTrue(client is RustClient)
        do {
            _ = try await client.projects()
            XCTFail("An unconfigured client must not return projects.")
        } catch KshiftClientError.ffiUnavailable(let reason) {
            XCTAssertTrue(reason.contains(key), reason)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
