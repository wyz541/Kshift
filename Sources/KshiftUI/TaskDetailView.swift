import KshiftCore
import SwiftUI

struct TaskDetailView: View {
    @ObservedObject var model: AppModel
    let taskID: String

    private var task: TaskItem? {
        model.task(withID: taskID)
    }

    var body: some View {
        Group {
            if let task {
                TaskEditorView(
                    model: model,
                    initialDraft: model.editDraft(for: task),
                    presentation: .sheet
                )
            } else {
                ContentUnavailableView(
                    "任务已不存在",
                    systemImage: "tray",
                    description: Text("共享快照可能已被其他编辑者更新。")
                )
                .frame(minWidth: 680, minHeight: 640)
            }
        }
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
