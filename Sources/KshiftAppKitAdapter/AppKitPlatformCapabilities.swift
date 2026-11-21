#if canImport(AppKit)
  import AppKit
  import Foundation
  import Security
  import UniformTypeIdentifiers
  import KshiftPresentation

  @MainActor
  public final class AppKitPlatformCapabilities: KshiftPlatformCapabilities {
    public let platform: KshiftPlatform = .macOS
    public let fetchReleaseResource: KshiftUpdateService.Fetch = { url in
      let (data, response) = try await URLSession.shared.data(from: url)
      guard let response = response as? HTTPURLResponse else {
        throw KshiftUpdateError.network("Expected an HTTP release response.")
      }
      return (data, response.statusCode)
    }

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

    public func installScrollWheelRouting() {
      AppKitScrollWheelRouter.shared.install()
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

    public func installUpdate(_ candidate: KshiftUpdateCandidate, data: Data) async -> KshiftUpdateInstallationResult {
      guard candidate.manifest.signingStatus == "signed" || candidate.asset.signingStatus == "signed" || candidate.asset.signingStatus == "notarized" else {
        return .rejected("The release is not signed for macOS.")
      }
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent("KshiftUpdate", isDirectory: true)
      do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(candidate.asset.name)
        try data.write(to: url, options: .atomic)
        guard verifyInstallerSignature(at: url) else {
          return .rejected("The downloaded installer signature is invalid.")
        }
        guard NSWorkspace.shared.open(url) else {
          return .rejected("macOS could not open the approved installer.")
        }
        return .opened
      } catch {
        return .rejected(error.localizedDescription)
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

    private func verifyInstallerSignature(at url: URL) -> Bool {
      switch url.pathExtension.lowercased() {
      case "app":
        return verifyCodeSignature(at: url)
      case "dmg":
        return runSecurityAssessment(at: url, type: "open")
      case "pkg":
        return runSecurityAssessment(at: url, type: "install")
      case "zip":
        let extractionDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KshiftUpdateExtract", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: extractionDirectory) }
        do {
          try FileManager.default.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)
          let unzip = Process()
          unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
          unzip.arguments = ["-q", "-o", url.path, "-d", extractionDirectory.path]
          try unzip.run()
          unzip.waitUntilExit()
          guard unzip.terminationStatus == 0,
                let app = FileManager.default.enumerator(at: extractionDirectory, includingPropertiesForKeys: nil)?
                    .compactMap({ $0 as? URL })
                    .first(where: { $0.pathExtension == "app" })
          else { return false }
          return verifyCodeSignature(at: app)
        } catch {
          return false
        }
      default:
        return false
      }
    }

    private func verifyCodeSignature(at url: URL) -> Bool {
      var staticCode: SecStaticCode?
      guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
            let staticCode
      else { return false }
      return SecStaticCodeCheckValidity(staticCode, [], nil) == errSecSuccess
    }

    private func runSecurityAssessment(at url: URL, type: String) -> Bool {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/sbin/spctl")
      process.arguments = ["--assess", "--type", type, "--context", "context:primary-signature", url.path]
      do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
      } catch {
        return false
      }
    }
  }
#endif
