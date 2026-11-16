import KshiftCore
import SwiftUI

struct FilterPopover: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private let contentWidth: CGFloat = 300

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: contentWidth, height: 580)
        .accessibilityIdentifier("filter-popover")
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("筛选与排序")
                    .font(.headline.weight(.semibold))
                Text(activeFilterCount == 0 ? "未启用筛选" : "\(activeFilterCount) 个条件已启用")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button("重置") {
                model.filter.reset()
                model.sortOption = .manual
            }
            .buttonStyle(.borderless)
            .disabled(!model.filter.isActive && model.sortOption == .manual)
            .accessibilityIdentifier("reset-filters")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                peopleSection
                statusSection
                prioritySection

                if !model.availableTags.isEmpty {
                    tagsSection
                }

                sortSection
            }
            .padding(16)
        }
    }

    private var peopleSection: some View {
        filterSection(
            "负责人",
            systemImage: "person.2",
            selectedCount: model.filter.assigneeIDs.count
        ) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 108), spacing: 8)],
                spacing: 8
            ) {
                ForEach(model.people) { person in
                    filterChip(
                        title: person.name,
                        systemImage: nil,
                        isSelected: model.filter.assigneeIDs.contains(person.id),
                        tint: .accentColor,
                        selectedForeground: .white
                    ) {
                        PersonAvatar(person: person, size: 20)
                    } action: {
                        setSelected(
                            model.filter.assigneeIDs.contains(person.id),
                            binding: assigneeBinding(person.id)
                        )
                    }
                    .accessibilityIdentifier("filter-assignee-\(person.id)")
                }

                filterChip(
                    title: "未分配",
                    systemImage: "person.crop.circle.badge.questionmark",
                    isSelected: model.filter.assigneeIDs.contains("unassigned"),
                    tint: .accentColor,
                    selectedForeground: .white
                ) {
                    EmptyView()
                } action: {
                    setSelected(
                        model.filter.assigneeIDs.contains("unassigned"),
                        binding: assigneeBinding("unassigned")
                    )
                }
                .accessibilityIdentifier("filter-assignee-unassigned")
            }
        }
    }

    private var statusSection: some View {
        filterSection(
            "状态",
            systemImage: "circle.dashed",
            selectedCount: model.filter.statuses.count
        ) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4),
                spacing: 6
            ) {
                ForEach(TaskStatus.allCases) { status in
                    compactChip(
                        title: status.title,
                        systemImage: status.symbol,
                        isSelected: model.filter.statuses.contains(status),
                        tint: status.tint
                    ) {
                        statusBinding(status).wrappedValue.toggle()
                    }
                    .accessibilityIdentifier("filter-status-\(status.rawValue)")
                }
            }
        }
    }

    private var prioritySection: some View {
        filterSection(
            "优先级",
            systemImage: "flag",
            selectedCount: model.filter.priorities.count
        ) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4),
                spacing: 6
            ) {
                ForEach(priorityOrder, id: \.self) { priority in
                    compactChip(
                        title: priority.code,
                        systemImage: nil,
                        isSelected: model.filter.priorities.contains(priority),
                        tint: priority.tint
                    ) {
                        priorityBinding(priority).wrappedValue.toggle()
                    }
                    .accessibilityLabel("\(priority.code) \(priority.title)")
                    .accessibilityIdentifier("filter-priority-\(priority.rawValue)")
                }
            }
        }
    }

    private var tagsSection: some View {
        filterSection(
            "标签",
            systemImage: "tag",
            selectedCount: model.filter.tags.count
        ) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 78), spacing: 6)],
                spacing: 6
            ) {
                ForEach(model.availableTags, id: \.self) { tag in
                    compactChip(
                        title: "#\(tag)",
                        systemImage: nil,
                        isSelected: model.filter.tags.contains(tag),
                        tint: .accentColor
                    ) {
                        tagBinding(tag).wrappedValue.toggle()
                    }
                    .accessibilityIdentifier("filter-tag-\(tag)")
                }
            }
        }
    }

    private var sortSection: some View {
        filterSection(
            "排序",
            systemImage: "arrow.up.arrow.down",
            selectedCount: model.sortOption == .manual ? 0 : 1
        ) {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                spacing: 8
            ) {
                ForEach(TaskSortOption.allCases) { option in
                    compactChip(
                        title: option.title,
                        systemImage: option == model.sortOption ? "checkmark" : nil,
                        isSelected: option == model.sortOption,
                        tint: .accentColor
                    ) {
                        model.sortOption = option
                    }
                    .accessibilityIdentifier("filter-sort-\(option.rawValue)")
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Label("\(model.filteredTasks.count) 项匹配", systemImage: "checklist")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Spacer()

            Button("完成") { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("close-filter-popover")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func filterSection<Content: View>(
        _ title: String,
        systemImage: String,
        selectedCount: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Label(title, systemImage: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                if selectedCount > 0 {
                    Text("\(selectedCount)")
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.tint.opacity(0.10), in: Capsule())
                }
            }

            content()
        }
    }

    private func filterChip<Leading: View>(
        title: String,
        systemImage: String?,
        isSelected: Bool,
        tint: Color,
        selectedForeground: Color,
        @ViewBuilder leading: () -> Leading,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                leading()

                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.semibold))
                        .accessibilityHidden(true)
                }

                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)

                Spacer(minLength: 2)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                }
            }
            .foregroundStyle(isSelected ? selectedForeground : Color.primary)
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .background(
                isSelected ? tint : Color.primary.opacity(0.05),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .strokeBorder(
                        isSelected ? tint.opacity(0.8) : Color.primary.opacity(0.08),
                        lineWidth: 1
                    )
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "已选择" : "未选择")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func compactChip(
        title: String,
        systemImage: String?,
        isSelected: Bool,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.semibold))
                        .accessibilityHidden(true)
                }

                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity, minHeight: 32)
            .padding(.horizontal, 5)
            .background(
                isSelected ? tint.opacity(0.18) : Color.primary.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected ? tint : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "已选择" : "未选择")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var activeFilterCount: Int {
        model.filter.assigneeIDs.count
            + model.filter.statuses.count
            + model.filter.priorities.count
            + model.filter.tags.count
    }

    private var priorityOrder: [TaskPriority] {
        [.urgent, .high, .medium, .low]
    }

    private func setSelected(_ isSelected: Bool, binding: Binding<Bool>) {
        binding.wrappedValue = !isSelected
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

    private func tagBinding(_ tag: String) -> Binding<Bool> {
        Binding(
            get: { model.filter.tags.contains(tag) },
            set: { enabled in
                if enabled {
                    model.filter.tags.insert(tag)
                } else {
                    model.filter.tags.remove(tag)
                }
            }
        )
    }
}
