import KshiftCore
import SwiftUI

struct PlannerView: View {
    @ObservedObject var model: AppModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isShowingFilters = false

    private var usesAccessibilityLayout: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private var projectTitleFont: Font {
        usesAccessibilityLayout ? .title2.weight(.bold) : .largeTitle.weight(.bold)
    }

    private var selectedDateTitle: String {
        model.selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 14)

                SummaryStrip(model: model)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 14)

                Divider()
                    .opacity(0.5)

                Group {
                    switch model.viewMode {
                    case .board:
                        BoardView(model: model)
                    case .calendar:
                        CalendarView(model: model)
                    case .table:
                        TaskTableView(model: model)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
            .background(.clear)
            .overlay(alignment: .bottomTrailing) {
                if horizontalSizeClass != .regular {
                    Button {
                        model.presentNewTask(assigneeID: nil)
                    } label: {
                        if usesAccessibilityLayout {
                            Image(systemName: "plus")
                                .font(.title3.weight(.semibold))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        } else {
                            Label("添加任务", systemImage: "plus")
                                .font(.headline)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .padding(20)
                    .accessibilityLabel("添加任务")
                    .accessibilityIdentifier("add-task")
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    if horizontalSizeClass == .regular {
                        Text(model.selectedProject?.name ?? "Kshift")
                            .font(projectTitleFont)
                            .lineLimit(usesAccessibilityLayout ? 2 : 1)
                    } else {
                        Menu {
                            ForEach(model.projects) { project in
                                Button {
                                    model.selectedProjectID = project.id
                                } label: {
                                    if project.id == model.selectedProjectID {
                                        Label(project.name, systemImage: "checkmark")
                                    } else {
                                        Text(project.name)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text(model.selectedProject?.name ?? "Kshift")
                                    .font(projectTitleFont)
                                    .lineLimit(usesAccessibilityLayout ? 2 : 1)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .frame(minHeight: 44, alignment: .leading)
                        .accessibilityLabel("切换项目，当前 \(model.selectedProject?.name ?? "Kshift")")
                        .accessibilityIdentifier("project-switcher")
                    }
                    Text(selectedDateTitle)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("正在刷新")
                }
            }

            plannerControls
        }
    }

    @ViewBuilder
    private var plannerControls: some View {
        if usesAccessibilityLayout {
            accessibilityControls
        } else if horizontalSizeClass == .regular {
            HStack(spacing: 10) {
                dateNavigation
                Spacer()
                utilityControls
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                dateNavigation

                Picker("规划视图", selection: $model.viewMode) {
                    ForEach(PlannerViewMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbol)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                compactActionBar
            }
        }
    }

    private var accessibilityControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            dateStepButtons
            datePickerControl

            Picker("规划视图", selection: $model.viewMode) {
                ForEach(PlannerViewMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbol)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)

            compactActionBar
        }
    }

    private var compactActionBar: some View {
        HStack(spacing: 8) {
            filterButton
            refreshButton
            Spacer()
            utilityControls
        }
    }

    private var filterButton: some View {
        Button {
            isShowingFilters.toggle()
        } label: {
            Image(systemName: model.filter.isActive
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease.circle")
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glass)
        .accessibilityLabel("筛选任务")
        .accessibilityIdentifier("filter-button")
        .popover(isPresented: $isShowingFilters, arrowEdge: .bottom) {
            FilterPopover(model: model)
        }
    }

    private var refreshButton: some View {
        Button {
            Swift.Task { await model.refresh() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glass)
        .accessibilityLabel("刷新共享快照")
        .accessibilityIdentifier("refresh-button")
    }

    private var dateNavigation: some View {
        HStack(spacing: 8) {
            dateStepButtons
            datePickerControl
        }
    }

    private var dateStepButtons: some View {
        HStack(spacing: 8) {
            Button {
                model.selectedDate = KshiftDate.addingDays(-1, to: model.selectedDate)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("前一天")

            Button {
                model.selectedDate = KshiftDate.startOfDay(.now)
            } label: {
                Image(systemName: "calendar.badge.clock")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("今天")

            Button {
                model.selectedDate = KshiftDate.addingDays(1, to: model.selectedDate)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("后一天")
        }
    }

    private var datePickerControl: some View {
        DatePicker(
            "选择日期",
            selection: $model.selectedDate,
            displayedComponents: .date
        )
        .labelsHidden()
        .fixedSize()
    }

    private var utilityControls: some View {
        HStack(spacing: 8) {
            Menu {
                Picker("排序", selection: $model.sortOption) {
                    ForEach(TaskSortOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .frame(width: 44, height: 44)
            }
            .menuStyle(.button)
            .buttonStyle(.glass)
            .accessibilityLabel("排序")
            .accessibilityIdentifier("sort-menu")

            Button {
                model.clearSelection()
            } label: {
                Image(systemName: "xmark.circle")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .disabled(model.selectedTaskIDs.isEmpty)
            .help("清除任务选择")
            .accessibilityLabel("清除选择")
            .accessibilityIdentifier("clear-selection")
        }
    }
}

struct SummaryStrip: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                SummaryMetric(
                    title: "当日任务",
                    value: String(model.selectedDateTasks.count),
                    symbol: "checklist",
                    tint: .blue
                )
                SummaryMetric(
                    title: "已完成",
                    value: String(model.completedToday),
                    symbol: "checkmark.circle.fill",
                    tint: .green
                )
                SummaryMetric(
                    title: "受阻",
                    value: String(model.blockedToday),
                    symbol: "exclamationmark.octagon.fill",
                    tint: .orange
                )
                SummaryMetric(
                    title: "完成率",
                    value: "\(completionPercent)%",
                    symbol: "chart.bar.fill",
                    tint: .purple
                )
            }
            .padding(.vertical, 2)
        }
    }

    private var completionPercent: Int {
        guard !model.selectedDateTasks.isEmpty else { return 0 }
        return Int(
            (Double(model.completedToday) / Double(model.selectedDateTasks.count) * 100)
                .rounded()
        )
    }
}

struct SummaryMetric: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.headline.monospacedDigit())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minWidth: 128, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)")
    }
}
