#if canImport(AppKit)
  import AppKit
  import SwiftUI

  @MainActor
  public struct AppKitWindowAccessor: NSViewRepresentable {
    private let onWindowChanged: @MainActor (NSWindow?) -> Void

    public init(onWindowChanged: @escaping @MainActor (NSWindow?) -> Void) {
      self.onWindowChanged = onWindowChanged
    }

    public func makeNSView(context: Context) -> WindowObservationView {
      let view = WindowObservationView()
      view.onWindowChanged = onWindowChanged
      return view
    }

    public func updateNSView(_ nsView: WindowObservationView, context: Context) {
      nsView.onWindowChanged = onWindowChanged
      nsView.reportWindow()
    }

    @MainActor
    public final class WindowObservationView: NSView {
      var onWindowChanged: (@MainActor (NSWindow?) -> Void)?

      public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportWindow()
      }

      func reportWindow() {
        onWindowChanged?(window)
      }
    }
  }
#endif
