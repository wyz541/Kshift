#if canImport(UIKit)
  import Foundation
  import KshiftPresentation
  import UIKit

  @MainActor
  public final class UIKitPlatformCapabilities: KshiftPlatformCapabilities {
    public let platform: KshiftPlatform = .iOS

    private let openURLHandler: @MainActor (URL) async -> Bool
    private let feedbackHandler: (KshiftPlatformFeedback) -> Void

    public init(
      openURLHandler: @escaping @MainActor (URL) async -> Bool = { url in
        await withCheckedContinuation { continuation in
          UIApplication.shared.open(url, options: [:]) { accepted in
            continuation.resume(returning: accepted)
          }
        }
      },
      feedbackHandler: @escaping (KshiftPlatformFeedback) -> Void = { feedback in
        switch feedback {
        case .selection:
          UISelectionFeedbackGenerator().selectionChanged()
        case .success:
          UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .error:
          UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
      }
    ) {
      self.openURLHandler = openURLHandler
      self.feedbackHandler = feedbackHandler
    }

    public func openExternalURL(_ url: URL) async -> Bool {
      await openURLHandler(url)
    }

    public func perform(_ feedback: KshiftPlatformFeedback) {
      feedbackHandler(feedback)
    }
  }
#endif
