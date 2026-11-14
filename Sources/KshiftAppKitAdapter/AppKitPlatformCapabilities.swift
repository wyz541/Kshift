#if canImport(AppKit)
  import AppKit
  import Foundation
  import UniformTypeIdentifiers
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

    public func exportImage(_ data: Data, suggestedFilename: String) async -> Bool {
      let panel = NSSavePanel()
      panel.allowedContentTypes = [.png]
      panel.nameFieldStringValue = suggestedFilename
      panel.canCreateDirectories = true
      guard panel.runModal() == .OK, let url = panel.url else {
        return false
      }
      do {
        try data.write(to: url, options: .atomic)
        return true
      } catch {
        return false
      }
    }

    public func printHTML(_ html: String, jobName: String) async -> Bool {
      guard let data = html.data(using: .utf8) else {
        return false
      }
      do {
        let attributed = try NSAttributedString(
          data: data,
          options: [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
          ],
          documentAttributes: nil
        )
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
        textView.textStorage?.setAttributedString(attributed)
        let operation = NSPrintOperation(view: textView)
        operation.jobTitle = jobName
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        return operation.run()
      } catch {
        return false
      }
    }
  }
#endif
