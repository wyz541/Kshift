import KshiftCore
import SwiftUI

struct TaskDetailView: View {
    @ObservedObject var model: AppModel
    let taskID: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isConfirmingDelete = false

    private var isCompactWidth: Bool {
        horizontalSizeClass == .compact
    }

    private var task: TaskItem? {
        model.task(withID: taskID)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let task {
                    taskContent(task)
                } else {
                    ContentUnavailableView(
                        "任务已不存在",
                        systemImage: "tray",
                        description: Text("共享快照可能已被其他编辑者更新。")
                    )
                }
            }
            .navigationTitle("任务详情")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .buttonStyle(.glass)
                }
                if let task {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            model.detailTaskID = nil
                            model.presentEdit(task)
                            dismiss()
                        } label: {
                            Label("编辑", systemImage: "pencil")
                        }
                        .buttonStyle(.glass)

                        Button(role: .destructive) {
                            isConfirmingDelete = true
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        .buttonStyle(.glass)
                    }
                }
            }
            .confirmationDialog(
                "删除任务？",
                isPresented: $isConfirmingDelete,
                presenting: task
            ) { task in
                Button("删除“\(task.title)”", role: .destructive) {
                    Swift.Task {
                        if await model.deleteTask(task) {
                            dismiss()
                        }
                    }
                }
                Button("取消", role: .cancel) {}
            } message: { _ in
                Text("删除会写入项目审计记录。此操作不能静默撤销。")
            }
            .frame(
                minWidth: isCompactWidth ? nil : 680,
                idealWidth: isCompactWidth ? nil : 720,
                minHeight: isCompactWidth ? nil : 640,
                idealHeight: isCompactWidth ? nil : 720
            )
        }
    }

    private func taskContent(_ task: TaskItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(task.title)
                            .font(.title.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 8) {
                            StatusBadge(status: task.status)
                            PriorityBadge(priority: task.priority)
                        }
                    }

                    Divider()

                    HStack(spacing: 20) {
                        DetailFact(title: "负责人", value: model.assigneeNames(for: task))
                        DetailFact(
                            title: "日期",
                            value: task.scheduleStartDate == task.scheduleEndDate
                                ? task.dueDate
                                : "\(task.scheduleStartDate) 至 \(task.scheduleEndDate)"
                        )
                        DetailFact(title: "版本", value: "v\(task.version)")
                    }
                }
                .padding(20)
                .background(
                    .primary.opacity(0.025),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.separator, lineWidth: 1)
                        .allowsHitTesting(false)
                }

                KshiftMarkdownText(
                    source: task.notes.isEmpty ? "暂无详情" : task.notes,
                    isPlaceholder: task.notes.isEmpty
                )
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    .primary.opacity(0.02),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.separator, lineWidth: 1)
                        .allowsHitTesting(false)
                }

                if !task.tags.isEmpty {
                    detailSection("标签") {
                        TaskTagList(tags: task.tags)
                    }
                }

                detailSection("历史") {
                    if task.history.isEmpty {
                        Text("暂无历史记录")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(task.history.reversed())) { entry in
                                HStack(alignment: .top, spacing: 12) {
                                    Circle()
                                        .fill(.tint)
                                        .frame(width: 8, height: 8)
                                        .padding(.top, 6)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(entry.summary)
                                            .font(.callout.weight(.medium))
                                        Text("\(model.actorName(for: entry.actorID)) · revision \(entry.revision)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(model.displayTimestamp(entry.occurredAt))
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 9)
                                .accessibilityIdentifier("task-history-\(entry.id)")
                                if entry.id != task.history.first?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .background(.background)
        .accessibilityIdentifier("task-detail")
    }

    private func detailSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

}

private struct DetailFact: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct StatusBadge: View {
    let status: TaskStatus

    var body: some View {
        Label(status.title, systemImage: status.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(status.tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(status.tint.opacity(0.12), in: Capsule())
    }
}

struct PriorityBadge: View {
    let priority: TaskPriority

    var body: some View {
        Label(priority.title, systemImage: "flag.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(priority.tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(priority.tint.opacity(0.12), in: Capsule())
    }
}
