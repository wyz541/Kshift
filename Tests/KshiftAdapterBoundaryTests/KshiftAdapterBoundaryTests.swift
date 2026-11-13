import Foundation
import KshiftPresentation
import XCTest

#if canImport(AppKit)
  import KshiftAppKitAdapter
#endif

#if canImport(UIKit)
  import KshiftUIKitAdapter
#endif

final class KshiftAdapterBoundaryTests: XCTestCase {
  #if canImport(AppKit)
    @MainActor
    func testAppKitAdapterUsesInjectedSystemBoundary() async {
      let url = URL(string: "https://example.com/appkit")!
      var openedURL: URL?
      var feedbackCount = 0
      let adapter = AppKitPlatformCapabilities(
        openURLHandler: { candidate in
          openedURL = candidate
          return true
        },
        feedbackHandler: { _ in
          feedbackCount += 1
        }
      )

      let accepted = await adapter.openExternalURL(url)
      adapter.perform(.success)

      XCTAssertTrue(accepted)
      XCTAssertEqual(openedURL, url)
      XCTAssertEqual(feedbackCount, 1)
      XCTAssertEqual(adapter.platform, .macOS)
    }
  #endif

  #if canImport(UIKit)
    @MainActor
    func testUIKitAdapterUsesInjectedSystemBoundary() async {
      let url = URL(string: "https://example.com/uikit")!
      var openedURL: URL?
      var feedbackCount = 0
      let adapter = UIKitPlatformCapabilities(
        openURLHandler: { candidate in
          openedURL = candidate
          return true
        },
        feedbackHandler: { _ in
          feedbackCount += 1
        }
      )

      let accepted = await adapter.openExternalURL(url)
      adapter.perform(.success)

      XCTAssertTrue(accepted)
      XCTAssertEqual(openedURL, url)
      XCTAssertEqual(feedbackCount, 1)
      XCTAssertEqual(adapter.platform, .iOS)
    }
  #endif
}
