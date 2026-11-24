#if canImport(AppKit)
  import AppKit

  @MainActor
  public final class AppKitScrollWheelRouter {
    public static let shared = AppKitScrollWheelRouter()

    private var monitor: Any?

    private init() {}

    public func install() {
      guard monitor == nil else { return }
      monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
        guard let self else { return event }
        let consumed = MainActor.assumeIsolated {
          self.route(event)
        }
        return consumed ? nil : event
      }
    }

    private func route(_ event: NSEvent) -> Bool {
      guard let window = event.window,
            let contentView = window.contentView
      else { return false }

      let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      if modifiers.contains(.command)
        || modifiers.contains(.option)
        || modifiers.contains(.control)
      {
        return false
      }

      return routeScroll(
        deltaX: event.scrollingDeltaX,
        deltaY: event.scrollingDeltaY,
        hasPreciseDeltas: event.hasPreciseScrollingDeltas,
        shift: modifiers.contains(.shift),
        in: contentView,
        at: event.locationInWindow
      )
    }

    @discardableResult
    func routeScroll(
      deltaX: CGFloat,
      deltaY: CGFloat,
      hasPreciseDeltas: Bool,
      shift: Bool,
      in contentView: NSView,
      at point: NSPoint
    ) -> Bool {
      if !shift, abs(deltaX) > abs(deltaY) {
        return false
      }

      let horizontal = shift
      let rawDelta = horizontal
        ? (deltaX != 0 ? deltaX : deltaY)
        : deltaY
      guard rawDelta != 0 else { return false }
      guard let scrollView = targetScrollView(
        in: contentView,
        containing: point,
        horizontal: horizontal
      ) else {
        return false
      }

      let scale: CGFloat = hasPreciseDeltas
        ? 1
        : (horizontal ? max(scrollView.horizontalLineScroll, 18) : max(scrollView.verticalLineScroll, 24))
      let delta = rawDelta * scale
      let clipView = scrollView.contentView
      var proposedBounds = clipView.bounds
      if horizontal {
        proposedBounds.origin.x -= delta
      } else {
        proposedBounds.origin.y -= delta
      }
      let constrained = clipView.constrainBoundsRect(proposedBounds)
      guard constrained.origin != clipView.bounds.origin else { return true }

      clipView.scroll(to: constrained.origin)
      scrollView.reflectScrolledClipView(clipView)
      return true
    }

    private func targetScrollView(
      in contentView: NSView,
      containing point: NSPoint,
      horizontal: Bool
    ) -> NSScrollView? {
      var candidates: [(scrollView: NSScrollView, depth: Int)] = []
      collectScrollViews(in: contentView, containing: point, depth: 0, into: &candidates)

      return candidates
        .filter { candidate in
          let clipView = candidate.scrollView.contentView
          let documentSize = clipView.documentRect.size
          let visibleSize = clipView.bounds.size
          if horizontal {
            return documentSize.width > visibleSize.width + 0.5
          }
          return documentSize.height > visibleSize.height + 0.5
        }
        .max { lhs, rhs in
          lhs.depth < rhs.depth
        }?
        .scrollView
    }

    private func collectScrollViews(
      in view: NSView,
      containing point: NSPoint,
      depth: Int,
      into result: inout [(scrollView: NSScrollView, depth: Int)]
    ) {
      guard !view.isHidden else { return }
      let frameInWindow = view.convert(view.bounds, to: nil)
      guard frameInWindow.contains(point) else { return }

      if let scrollView = view as? NSScrollView {
        result.append((scrollView, depth))
      }
      for subview in view.subviews {
        collectScrollViews(
          in: subview,
          containing: point,
          depth: depth + 1,
          into: &result
        )
      }
    }
  }
#endif
