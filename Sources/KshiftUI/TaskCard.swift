import KshiftCore
import SwiftUI

struct TaskCard: View {
    @ObservedObject var model: AppModel
    let task: TaskItem
    let isSelected: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Button {
                    Swift.Task { await model.toggleDone(task) }
                } label: {
                    Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(task.status == .done ? completionTint : .secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(task.status == .done ? "标记为待处理" : "标记为已完成")
                .accessibilityHint("更新共享任务状态")
                .accessibilityIdentifier("toggle-task-\(task.id)")

                VStack(alignment: .leading, spacing: 5) {
                    Text(task.title)
                        .font(.headline)
                        .strikethrough(task.status == .done)
                        .foregroundStyle(.primary)

                    if !task.notes.isEmpty {
                        Text(task.notes)
                            .font(.caption)
                            .foregroundStyle(.primary)
                    }
                }
                .accessibilityHidden(true)

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Image(systemName: "flag.fill")
                    .foregroundStyle(task.priority.tint)
                Image(systemName: task.status.symbol)
                    .foregroundStyle(task.status.tint)
                Spacer()
                AssigneeAvatarStack(people: assignees, size: 23)
            }
            .font(.callout)
            .accessibilityHidden(true)

            HStack {
                Spacer()
                Menu {
                    Button {
                        model.presentEdit(task)
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                    Button {
                        model.presentDetails(task)
                    } label: {
                        Label("查看历史和详情", systemImage: "clock")
                    }
                    Divider()
                    Button(role: .destructive) {
                        model.requestDelete(task)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .accessibilityLabel("任务操作")
            }
        }
        .padding(10)
        .kshiftContentBoard()
        .kshiftGlassCard()
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.tint, lineWidth: 2)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture {
            model.presentDetails(task)
        }
        .draggable(task.id)
        .contextMenu {
            Button("编辑") { model.presentEdit(task) }
            Button(task.status == .done ? "标记为待处理" : "标记为已完成") {
                Swift.Task { await model.toggleDone(task) }
            }
            Divider()
            Button("删除", role: .destructive) { model.requestDelete(task) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(task.title)，\(task.status.title)，\(task.priority.title)优先级")
        .accessibilityValue("负责人 \(assigneeNames)，版本 \(task.version)")
        .accessibilityHint("打开任务详情")
        .accessibilityIdentifier("task-\(task.id)")
    }

    private var completionTint: Color {
        colorScheme == .dark ? Color(hex: "#5FDD8B") : Color(hex: "#116B2C")
    }

    private var assignees: [Person] {
        task.assigneeIDs.compactMap { id in model.people.first(where: { $0.id == id }) }
    }

    private var assigneeNames: String {
        task.assigneeIDs.isEmpty ? "未分配" : model.assigneeNames(for: task)
    }
}

struct AssigneeAvatarStack: View {
    let people: [Person]
    let size: CGFloat

    var body: some View {
        if people.isEmpty {
            PersonAvatar(
                person: Person(id: "unassigned", name: "未分配", initials: "—", colorHex: "#8E8E93"),
                size: size
            )
        } else {
            HStack(spacing: -6) {
                ForEach(Array(people.prefix(3))) { person in
                    PersonAvatar(person: person, size: size)
                }
                if people.count > 3 {
                    Text("+\(people.count - 3)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                }
            }
        }
    }
}

struct CompactTaskRow: View {
    @ObservedObject var model: AppModel
    let task: TaskItem

    var body: some View {
        Button {
            model.presentDetails(task)
        } label: {
            HStack {
                Image(systemName: task.status.symbol)
                    .foregroundStyle(task.status.tint)
                Text(task.title)
                    .lineLimit(1)
                Spacer()
                Text(task.priority.title)
                    .font(.caption)
                    .foregroundStyle(task.priority.tint)
            }
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("compact-task-\(task.id)")
    }
}
