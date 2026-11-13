#if canImport(AppKit)
  import AppKit
  import Foundation
  import KshiftPresentation

  @MainActor
  public final class AppKitPlatformCapabilities: KshiftPlatformCapabilities {
    public let platform: KshiftPlatform = .macOS

    private let openURLHandler: (URL) -> Bool
    private let feedbackHandler: (KshiftPlatformFeedback) -> Void

    public init(
      openURLHandler: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
      feedbackHandler: @escaping (KshiftPlatformFeedback) -> Void = { feedback in
        let pattern: NSHapticFeedbackManager.FeedbackPattern =
          switch feedback {
          case .selection:
            .alignment
          case .success:
            .levelChange
          case .error:
            .generic
          }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
      }
    ) {
      self.openURLHandler = openURLHandler
      self.feedbackHandler = feedbackHandler
    }

    public func openExternalURL(_ url: URL) async -> Bool {
      openURLHandler(url)
    }

    public func perform(_ feedback: KshiftPlatformFeedback) {
      feedbackHandler(feedback)
    }
  }
#endif
