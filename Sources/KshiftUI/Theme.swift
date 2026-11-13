import KshiftCore
import SwiftUI

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
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .padding(3)
            .background {
                if reduceTransparency || contrast == .increased {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.background)
                }
            }
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: false)
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
