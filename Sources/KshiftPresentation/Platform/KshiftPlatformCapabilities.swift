import Foundation

public enum KshiftPlatform: String, Sendable {
  case macOS
  case iOS
}

public enum KshiftUpdateInstallationResult: Equatable, Sendable {
  case opened
  case rejected(String)
  case unsupported(String)
}

public enum KshiftPlatformFeedback: Equatable, Sendable {
  case selection
  case success
  case error
}

@MainActor
public protocol KshiftPlatformCapabilities: AnyObject {
  var platform: KshiftPlatform { get }
  var fetchReleaseResource: KshiftUpdateService.Fetch { get }
  func openExternalURL(_ url: URL) async -> Bool
  func perform(_ feedback: KshiftPlatformFeedback)
  func exportImage(_ data: Data, suggestedFilename: String) async -> Bool
  func printHTML(_ html: String, jobName: String) async -> Bool
  func installUpdate(_ candidate: KshiftUpdateCandidate, data: Data) async -> KshiftUpdateInstallationResult
}

public extension KshiftPlatformCapabilities {
  var fetchReleaseResource: KshiftUpdateService.Fetch {
    { _ in throw KshiftUpdateError.network("Release downloads are not available on this platform.") }
  }

  func exportImage(_ data: Data, suggestedFilename: String) async -> Bool {
    _ = data
    _ = suggestedFilename
    return true
  }

  func printHTML(_ html: String, jobName: String) async -> Bool {
    _ = html
    _ = jobName
    return true
  }

  func installUpdate(_ candidate: KshiftUpdateCandidate, data: Data) async -> KshiftUpdateInstallationResult {
    _ = candidate
    _ = data
    return .unsupported("This platform does not provide an installer.")
  }
}

@MainActor
public final class KshiftNoopPlatformCapabilities: KshiftPlatformCapabilities {
  public let platform: KshiftPlatform

  public init(platform: KshiftPlatform = .macOS) {
    self.platform = platform
  }

  public func openExternalURL(_ url: URL) async -> Bool {
    true
  }

  public func perform(_ feedback: KshiftPlatformFeedback) {}
}
