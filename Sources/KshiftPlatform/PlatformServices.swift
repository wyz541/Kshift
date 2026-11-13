#if os(macOS)
import AppKit
import KshiftUI

@MainActor
public final class MacPlatformServices: PlatformServices {
    public init() {}

    public func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    public func successHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
#elseif os(iOS)
import UIKit
import KshiftUI

@MainActor
public final class IOSPlatformServices: PlatformServices {
    public init() {}

    public func openAccessibilitySettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    public func successHaptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
#endif
