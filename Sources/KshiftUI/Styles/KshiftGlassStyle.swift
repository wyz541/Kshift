import SwiftUI

public struct KshiftGlassGroup<Content: View>: View {
  private let spacing: CGFloat
  private let content: Content

  public init(spacing: CGFloat = 12, @ViewBuilder content: () -> Content) {
    self.spacing = spacing
    self.content = content()
  }

  public var body: some View {
    GlassEffectContainer(spacing: spacing) {
      content
    }
  }
}

public struct KshiftInteractiveGlassCard<Content: View>: View {
  private let action: () -> Void
  private let content: Content

  public init(action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
    self.action = action
    self.content = content()
  }

  public var body: some View {
    Button(action: action) {
      content
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: shape)
        .overlay {
          shape.strokeBorder(borderColor, lineWidth: borderWidth)
        }
        .contentShape(shape)
    }
    .buttonStyle(.plain)
    .modifier(KshiftGlassSurfaceModifier(shape: shape))
  }

  @Environment(\.colorSchemeContrast) private var colorSchemeContrast

  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: 20, style: .continuous)
  }

  private var borderColor: Color {
    colorSchemeContrast == .increased ? .primary : .primary.opacity(0.12)
  }

  private var borderWidth: CGFloat {
    colorSchemeContrast == .increased ? 2 : 1
  }
}

private struct KshiftGlassSurfaceModifier<S: Shape>: ViewModifier {
  let shape: S

  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  @ViewBuilder
  func body(content: Content) -> some View {
    if reduceTransparency {
      content
        .background(.regularMaterial, in: shape)
        .clipShape(shape)
    } else {
      content
        .glassEffect(.regular.interactive(), in: shape)
    }
  }
}

public struct KshiftPrimaryGlassButton<Label: View>: View {
  private let action: () -> Void
  private let label: Label

  public init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
    self.action = action
    self.label = label()
  }

  public var body: some View {
    Button(action: action) {
      label
        .font(.headline.weight(.semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .background(.regularMaterial, in: shape)
        .overlay {
          shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .contentShape(shape)
    }
    .buttonStyle(.plain)
    .modifier(KshiftGlassSurfaceModifier(shape: shape))
    .frame(minHeight: 44)
  }

  private var shape: Capsule {
    Capsule(style: .continuous)
  }
}

public struct KshiftSecondaryGlassButton<Label: View>: View {
  private let action: () -> Void
  private let label: Label

  public init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
    self.action = action
    self.label = label()
  }

  public var body: some View {
    Button(action: action) {
      label
        .frame(minHeight: 28)
    }
    .buttonStyle(.glass)
    .controlSize(.large)
    .frame(minHeight: 44)
  }
}
