import KshiftCore
import SwiftUI

struct FilterPopover: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("筛选与排序")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("重置") {
                    model.filter.reset()
                    model.sortOption = .manual
                }
                .buttonStyle(.glass)
                .disabled(!model.filter.isActive && model.sortOption == .manual)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    filterSection("负责人") {
                        ForEach(model.people) { person in
                            Toggle(isOn: assigneeBinding(person.id)) {
                                HStack {
                                    PersonAvatar(person: person, size: 24)
                                    Text(person.name)
                                }
                            }
                            .toggleStyle(.switch)
                        }
                        Toggle("未分配", isOn: assigneeBinding("unassigned"))
                            .toggleStyle(.switch)
                    }

                    filterSection("状态") {
                        ForEach(TaskStatus.allCases) { status in
                            Toggle(isOn: statusBinding(status)) {
                                Label(status.title, systemImage: status.symbol)
                            }
                            .toggleStyle(.switch)
                        }
                    }

                    filterSection("优先级") {
                        ForEach(TaskPriority.allCases) { priority in
                            Toggle(priority.title, isOn: priorityBinding(priority))
                                .toggleStyle(.switch)
                        }
                    }

                    filterSection("排序") {
                        Picker("排序方式", selection: $model.sortOption) {
                            ForEach(TaskSortOption.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.inline)
                    }
                }
            }

            HStack {
                Text("\(model.filteredTasks.count) 项匹配")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("完成") { dismiss() }
                    .buttonStyle(.glassProminent)
            }
        }
        .padding(18)
        .frame(idealWidth: 340, idealHeight: 520)
        .accessibilityIdentifier("filter-popover")
    }

    private func filterSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    private func assigneeBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { model.filter.assigneeIDs.contains(id) },
            set: { enabled in
                if enabled {
                    model.filter.assigneeIDs.insert(id)
                } else {
                    model.filter.assigneeIDs.remove(id)
                }
            }
        )
    }

    private func statusBinding(_ status: TaskStatus) -> Binding<Bool> {
        Binding(
            get: { model.filter.statuses.contains(status) },
            set: { enabled in
                if enabled {
                    model.filter.statuses.insert(status)
                } else {
                    model.filter.statuses.remove(status)
                }
            }
        )
    }

    private func priorityBinding(_ priority: TaskPriority) -> Binding<Bool> {
        Binding(
            get: { model.filter.priorities.contains(priority) },
            set: { enabled in
                if enabled {
                    model.filter.priorities.insert(priority)
                } else {
                    model.filter.priorities.remove(priority)
                }
            }
        )
    }
}
