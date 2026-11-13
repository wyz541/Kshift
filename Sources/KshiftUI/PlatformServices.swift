import Foundation

@MainActor
public protocol PlatformServices: AnyObject {
    func openAccessibilitySettings()
    func successHaptic()
}

@MainActor
public final class PreviewPlatformServices: PlatformServices {
    public init() {}
    public func openAccessibilitySettings() {}
    public func successHaptic() {}
}
