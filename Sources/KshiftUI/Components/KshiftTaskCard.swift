import KshiftPresentation
import SwiftUI

public struct KshiftTaskCard: View {
  private let task: KshiftTaskItemPresentation
  private let isPending: Bool
  private let action: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public init(
    task: KshiftTaskItemPresentation,
    isPending: Bool,
    action: @escaping () -> Void
  ) {
    self.task = task
    self.isPending = isPending
    self.action = action
  }

  public var body: some View {
    KshiftInteractiveGlassCard(action: action) {
      HStack(alignment: .top, spacing: 14) {
        statusIndicator
        VStack(alignment: .leading, spacing: 8) {
          Text(task.title)
            .font(.headline)
            .foregroundStyle(.primary)
            .strikethrough(task.isCompleted)
          if let details = task.details {
            Text(details)
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .lineLimit(2)
          }
          HStack(spacing: 8) {
            KshiftSemanticBadge(task.statusLabel, role: task.statusRole)
            KshiftSemanticBadge("优先级 \(task.priorityLabel)", role: task.priorityRole)
            Label(task.assigneeLabel, systemImage: "person")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        Spacer(minLength: 8)
        if isPending {
          ProgressView()
            .controlSize(.small)
            .accessibilityLabel("正在更新任务")
        }
      }
    }
    .disabled(isPending)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(task.accessibilityLabel)
    .accessibilityHint(task.accessibilityHint)
    .accessibilityAddTraits(task.isCompleted ? .isSelected : [])
    .animation(reduceMotion ? nil : .snappy, value: isPending)
  }

  private var statusIndicator: some View {
    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
      .font(.title3)
      .foregroundStyle(Color.kshift(task.isCompleted ? .success : .accent))
      .frame(width: 28, height: 28)
      .accessibilityHidden(true)
  }
}
