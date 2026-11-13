import KshiftPresentation
import SwiftUI

public struct KshiftSemanticBadge: View {
  private let text: String
  private let role: KshiftSemanticRole

  public init(_ text: String, role: KshiftSemanticRole) {
    self.text = text
    self.role = role
  }

  public var body: some View {
    Text(text)
      .font(.caption.weight(.semibold))
      .foregroundStyle(Color.kshift(role))
      .padding(.horizontal, 9)
      .padding(.vertical, 5)
      .background(Color.kshift(role).opacity(0.12), in: Capsule())
      .overlay {
        Capsule()
          .strokeBorder(Color.kshift(role).opacity(0.28), lineWidth: 1)
      }
      .accessibilityLabel(text)
  }
}
