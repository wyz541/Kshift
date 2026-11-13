import XCTest

final class KshiftIOSTests: XCTestCase {
    func testAppBundleUsesKshiftIdentifier() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.wyz541.kshift.ios")
    }
}
