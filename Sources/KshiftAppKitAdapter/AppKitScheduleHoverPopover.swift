#if canImport(AppKit)
import AppKit
import SwiftUI

public struct AppKitScheduleHoverPopover: NSViewRepresentable {
    private let isPresented: Bool
    private let preview: AnyView

    public init(isPresented: Bool, preview: AnyView) {
        self.isPresented = isPresented
        self.preview = preview
    }

    public func makeNSView(context: Context) -> Anchor { Anchor() }

    public func updateNSView(_ anchor: Anchor, context: Context) {
        guard isPresented, anchor.window != nil else {
            anchor.popover.close()
            return
        }
        if let host = anchor.popover.contentViewController as? NSHostingController<AnyView> {
            host.rootView = preview
        } else {
            anchor.popover.contentViewController = NSHostingController(rootView: preview)
        }
        if !anchor.popover.isShown {
            anchor.popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxX)
        }
    }

    public static func dismantleNSView(_ anchor: Anchor, coordinator: ()) {
        anchor.popover.close()
    }

    public final class Anchor: NSView {
        let popover: NSPopover = {
            let popover = NSPopover()
            // The click that closes a hover preview must still reach the task bar.
            popover.behavior = .applicationDefined
            popover.animates = false
            return popover
        }()

        public override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
#endif
