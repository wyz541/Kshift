import KshiftPresentation
import SwiftUI

extension Color {
  public static func kshift(_ role: KshiftSemanticRole) -> Color {
    switch role {
    case .primary:
      .primary
    case .secondary:
      .secondary
    case .accent:
      .accentColor
    case .success:
      .green
    case .warning:
      .orange
    case .danger:
      .red
    case .neutral:
      .gray
    }
  }
}

public struct KshiftScreenBackground: ViewModifier {
  public init() {}

  public func body(content: Content) -> some View {
    content
      .background(Color.accentColor.opacity(0.045))
      .background(.background)
  }
}

extension View {
  public func kshiftScreenBackground() -> some View {
    modifier(KshiftScreenBackground())
  }
}
