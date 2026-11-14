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

    public func exportImage(_ data: Data, suggestedFilename: String) async -> Bool {
      let url = FileManager.default.temporaryDirectory.appendingPathComponent(suggestedFilename)
      do {
        try data.write(to: url, options: .atomic)
      } catch {
        return false
      }
      return await withCheckedContinuation { continuation in
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
          continuation.resume(returning: completed)
        }
        topViewController()?.present(controller, animated: true)
      }
    }

    public func printHTML(_ html: String, jobName: String) async -> Bool {
      let controller = UIPrintInteractionController.shared
      let information = UIPrintInfo.printInfo()
      information.jobName = jobName
      information.outputType = .general
      controller.printInfo = information
      controller.printFormatter = UIMarkupTextPrintFormatter(markupText: html)
      return await withCheckedContinuation { continuation in
        controller.present(animated: true) { _, completed, _ in
          continuation.resume(returning: completed)
        }
      }
    }

    private func topViewController() -> UIViewController? {
      let scene = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .first { $0.activationState == .foregroundActive }
      var controller = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
      while let presented = controller?.presentedViewController {
        controller = presented
      }
      return controller
    }
  }
#endif
