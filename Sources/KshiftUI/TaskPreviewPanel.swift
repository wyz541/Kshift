import KshiftCore
import SwiftUI

struct TaskPreviewPanel: View {
    @ObservedObject var model: AppModel
    let task: TaskItem

    private var dateLabel: String {
        task.scheduleStartDate == task.scheduleEndDate
            ? task.dueDate
            : "\(task.scheduleStartDate) – \(task.scheduleEndDate)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(task.title)
                .font(.headline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                StatusBadge(status: task.status)
                PriorityBadge(priority: task.priority)
            }

            VStack(alignment: .leading, spacing: 5) {
                Label(model.assigneeNames(for: task), systemImage: "person")
                Label(dateLabel, systemImage: "calendar")
                if !task.tags.isEmpty {
                    Label(task.tags.map { "#\($0)" }.joined(separator: "  "), systemImage: "tag")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()

            Text("详情")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ScrollView {
                KshiftMarkdownText(
                    source: task.notes.isEmpty ? "暂无详情" : task.notes,
                    isPlaceholder: task.notes.isEmpty
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)
        }
        .padding(16)
        .frame(width: 360, alignment: .leading)
        .background(.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("task-preview-\(task.id)")
    }
}

struct ScheduleTaskHoverPreviewModifier: ViewModifier {
    @ObservedObject var model: AppModel
    let task: TaskItem

    @State private var isHovering = false
    @State private var isPresenting = false
    @State private var delayedPresentation: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovering = hovering
                delayedPresentation?.cancel()
                if hovering {
                    delayedPresentation = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(450))
                        guard !Task.isCancelled, isHovering else { return }
                        isPresenting = true
                    }
                } else {
                    isPresenting = false
                }
            }
            .popover(
                isPresented: $isPresenting,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .trailing
            ) {
                TaskPreviewPanel(model: model, task: task)
            }
            .onDisappear {
                delayedPresentation?.cancel()
                isPresenting = false
            }
    }
}
