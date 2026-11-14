import Foundation

public enum KshiftPlatform: String, Sendable {
  case macOS
  case iOS
}

public enum KshiftPlatformFeedback: Equatable, Sendable {
  case selection
  case success
  case error
}

@MainActor
public protocol KshiftPlatformCapabilities: AnyObject {
  var platform: KshiftPlatform { get }
  func openExternalURL(_ url: URL) async -> Bool
  func perform(_ feedback: KshiftPlatformFeedback)
  func exportImage(_ data: Data, suggestedFilename: String) async -> Bool
  func printHTML(_ html: String, jobName: String) async -> Bool
}

public extension KshiftPlatformCapabilities {
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
