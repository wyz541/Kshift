import Foundation
import KshiftPresentation
import XCTest

#if canImport(AppKit)
  import AppKit
  @testable import KshiftAppKitAdapter
#endif

#if canImport(UIKit)
  import KshiftUIKitAdapter
#endif

final class KshiftAdapterBoundaryTests: XCTestCase {
  #if canImport(AppKit)
    @MainActor
    func testScrollWheelRoutesVerticalAndShiftHorizontal() {
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
        styleMask: .borderless,
        backing: .buffered,
        defer: false
      )
      window.isReleasedWhenClosed = false

      let outerScroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
      outerScroll.hasVerticalScroller = true
      let outerDocument = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 1_000))
      outerScroll.documentView = outerDocument

      let innerScroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
      innerScroll.hasHorizontalScroller = true
      let innerDocument = NSView(frame: NSRect(x: 0, y: 0, width: 2_000, height: 200))
      innerScroll.documentView = innerDocument
      outerDocument.addSubview(innerScroll)

      window.contentView = outerScroll
      window.layoutIfNeeded()
      outerScroll.layoutSubtreeIfNeeded()
      innerScroll.layoutSubtreeIfNeeded()

      let point = NSPoint(x: 150, y: 100)
      let router = AppKitScrollWheelRouter.shared
      XCTAssertTrue(
        router.routeScroll(
          deltaX: 0,
          deltaY: -80,
          hasPreciseDeltas: true,
          shift: false,
          in: outerScroll,
          at: point
        )
      )
      XCTAssertGreaterThan(outerScroll.contentView.bounds.origin.y, 0)
      XCTAssertEqual(innerScroll.contentView.bounds.origin.x, 0)

      XCTAssertTrue(
        router.routeScroll(
          deltaX: 0,
          deltaY: -80,
          hasPreciseDeltas: true,
          shift: true,
          in: outerScroll,
          at: point
        )
      )
      XCTAssertGreaterThan(innerScroll.contentView.bounds.origin.x, 0)
    }

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
