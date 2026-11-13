import KshiftCore
import SwiftUI

public struct KshiftForceReduceTransparencyKey: EnvironmentKey {
    public static let defaultValue = false
}

public extension EnvironmentValues {
    var kshiftForceReduceTransparency: Bool {
        get { self[KshiftForceReduceTransparencyKey.self] }
        set { self[KshiftForceReduceTransparencyKey.self] = newValue }
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red: UInt64
        let green: UInt64
        let blue: UInt64
        let alpha: UInt64
        switch cleaned.count {
        case 8:
            red = value >> 24
            green = (value >> 16) & 0xFF
            blue = (value >> 8) & 0xFF
            alpha = value & 0xFF
        default:
            red = value >> 16
            green = (value >> 8) & 0xFF
            blue = value & 0xFF
            alpha = 0xFF
        }
        self.init(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: Double(alpha) / 255
        )
    }
}

extension TaskStatus {
    var tint: Color {
        switch self {
        case .todo: .secondary
        case .inProgress: .blue
        case .blocked: .orange
        case .done: .green
        }
    }
}

extension TaskPriority {
    var tint: Color {
        switch self {
        case .low: .secondary
        case .medium: .blue
        case .high: .orange
        case .urgent: .red
        }
    }
}

struct ContentBoard: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(.background)
            )
            .overlay {
                if contrast == .increased {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(.primary, lineWidth: 1.5)
                }
            }
    }
}

struct GlassCardSurface: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.kshiftForceReduceTransparency) private var forceReduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        if reduceTransparency || forceReduceTransparency {
            content
                .padding(3)
                .background(.background, in: shape)
                .overlay {
                    shape.strokeBorder(.separator, lineWidth: contrast == .increased ? 2 : 1)
                }
        } else {
            content
                .padding(3)
                .glassEffect(.regular, in: shape)
                .overlay {
                    if contrast == .increased {
                        shape.strokeBorder(.primary, lineWidth: 2)
                    }
                }
                .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: false)
        }
    }
}

extension View {
    func kshiftContentBoard() -> some View {
        modifier(ContentBoard())
    }

    func kshiftGlassCard() -> some View {
        modifier(GlassCardSurface())
    }
}
