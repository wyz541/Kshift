import KshiftCore
import SwiftUI

struct TaskTableView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    if model.filteredTasks.isEmpty {
                        ContentUnavailableView(
                            "没有匹配任务",
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text("修改搜索词或筛选条件。")
                        )
                        .frame(minWidth: 760, minHeight: 280)
                    } else {
                        ForEach(model.filteredTasks) { task in
                            TaskTableRow(model: model, task: task)
                            Divider()
                        }
                    }
                } header: {
                    tableHeader
                }
            }
            .frame(minWidth: 900)
        }
        .background(.background)
        .accessibilityIdentifier("table-view")
    }

    private var tableHeader: some View {
        HStack(spacing: 0) {
            Button {
                toggleAll()
            } label: {
                Image(systemName: allSelected ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(allSelected ? "取消全选" : "全选当前任务")

            headerCell("任务", width: 320, alignment: .leading)
            headerCell("状态", width: 120)
            headerCell("优先级", width: 100)
            headerCell("负责人", width: 150)
            headerCell("日期", width: 120)
            headerCell("版本", width: 76)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .background(.bar)
    }

    private func headerCell(
        _ title: String,
        width: CGFloat,
        alignment: Alignment = .center
    ) -> some View {
        Text(title)
            .frame(width: width, alignment: alignment)
            .padding(.horizontal, 8)
    }

    private var allSelected: Bool {
        !model.filteredTasks.isEmpty
            && Set(model.filteredTasks.map(\.id)).isSubset(of: model.selectedTaskIDs)
    }

    private func toggleAll() {
        if allSelected {
            model.clearSelection()
        } else {
            for task in model.filteredTasks where !model.selectedTaskIDs.contains(task.id) {
                model.toggleSelection(task.id)
            }
        }
    }
}

private struct TaskTableRow: View {
    @ObservedObject var model: AppModel
    let task: TaskItem

    var body: some View {
        HStack(spacing: 0) {
            Button {
                model.toggleSelection(task.id)
            } label: {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .frame(width: 44, height: 48)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSelected ? "取消选择 \(task.title)" : "选择 \(task.title)")

            Button {
                model.presentDetails(task)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if !task.notes.isEmpty {
                        Text(task.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(width: 320, alignment: .leading)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                ForEach(TaskStatus.allCases) { status in
                    Button {
                        setStatus(status)
                    } label: {
                        Label(status.title, systemImage: status.symbol)
                    }
                }
            } label: {
                Text(task.status.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(task.status.tint)
                    .frame(width: 120)
                    .frame(minHeight: 44)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)

            Text(task.priority.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(task.priority.tint)
                .frame(width: 100)
                .frame(minHeight: 44)

            HStack(spacing: 7) {
                PersonAvatar(person: person, size: 24)
                Text(person.name)
                    .font(.caption)
                    .lineLimit(1)
            }
            .frame(width: 150, alignment: .center)

            Text(task.dueDate)
                .font(.caption.monospacedDigit())
                .frame(width: 120)

            Text("v\(task.version)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 76)
        }
        .padding(.horizontal, 12)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
        .contextMenu {
            Button("编辑") { model.presentEdit(task) }
            Button("详情") { model.presentDetails(task) }
            Divider()
            Button("删除", role: .destructive) { model.requestDelete(task) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("table-task-\(task.id)")
    }

    private var isSelected: Bool {
        model.selectedTaskIDs.contains(task.id)
    }

    private var person: Person {
        model.people.first(where: { $0.id == task.assigneeID })
            ?? Person(id: "unassigned", name: "未分配", initials: "—", colorHex: "#8E8E93")
    }

    private func setStatus(_ status: TaskStatus) {
        Swift.Task { await model.setStatus(task, to: status) }
    }
}

struct BulkActionBar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Label("\(model.selectedTaskIDs.count) 项已选择", systemImage: "checkmark.circle")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 4)

                Menu {
                    ForEach(TaskStatus.allCases) { status in
                        Button(status.title) {
                            Swift.Task { await model.setStatusForSelection(status) }
                        }
                    }
                } label: {
                    Label("修改状态", systemImage: "arrow.triangle.2.circlepath")
                }
                .menuStyle(.button)
                .buttonStyle(.glass)

                Button {
                    model.clearSelection()
                } label: {
                    Label("清除", systemImage: "xmark")
                }
                .buttonStyle(.glass)
            }
            .padding(10)
            .glassEffect(.regular, in: Capsule())
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bulk-action-bar")
    }
}
