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
}

@MainActor
public final class KshiftNoopPlatformCapabilities: KshiftPlatformCapabilities {
  public let platform: KshiftPlatform

  public init(platform: KshiftPlatform) {
    self.platform = platform
  }

  public func openExternalURL(_ url: URL) async -> Bool {
    true
  }

  public func perform(_ feedback: KshiftPlatformFeedback) {}
}
