import KshiftCore
import SwiftUI

struct TaskDetailView: View {
    @ObservedObject var model: AppModel
    let taskID: String
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDelete = false

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
            .frame(idealWidth: 620, idealHeight: 720)
        }
    }

    private func taskContent(_ task: TaskItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(task.title)
                        .font(.largeTitle.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        StatusBadge(status: task.status)
                        PriorityBadge(priority: task.priority)
                    }
                }

                HStack(spacing: 18) {
                    DetailFact(title: "负责人", value: personName(task.assigneeID))
                    DetailFact(title: "日期", value: task.dueDate)
                    DetailFact(title: "版本", value: "v\(task.version)")
                }
                .padding(16)
                .kshiftContentBoard()

                detailSection("说明") {
                    Text(task.notes.isEmpty ? "无说明" : task.notes)
                        .foregroundStyle(task.notes.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                }

                detailSection("历史") {
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
                                    Text(entry.occurredAt)
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 9)
                            if entry.id != task.history.first?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding(22)
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

    private func personName(_ id: String?) -> String {
        guard let id else { return "未分配" }
        return model.actorName(for: id)
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
