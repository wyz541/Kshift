import KshiftCore
import SwiftUI

struct PeopleScheduleView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var horizontalOffset: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0
    @State private var isShowingSettings = false
    @State private var hasRestoredScroll = false

    private var rows: [PeopleScheduleRow] {
        var result = model.people.map { person in
            makeRow(
                id: person.id,
                person: person,
                tasks: model.filteredTasks.filter { $0.assigneeIDs.contains(person.id) }
            )
        }
        let unassigned = model.filteredTasks.filter(\.assigneeIDs.isEmpty)
        if !unassigned.isEmpty {
            let row = makeRow(id: "unassigned", person: nil, tasks: unassigned)
            if !row.slices.isEmpty {
                result.append(row)
            }
        }
        return result
    }

    private var dateWidth: CGFloat {
        dynamicTypeSize.isAccessibilitySize
            ? max(model.scheduleDateColumnWidth, 160)
            : model.scheduleDateColumnWidth
    }
    private var peopleWidth: CGFloat {
        dynamicTypeSize.isAccessibilitySize
            ? max(model.schedulePeopleColumnWidth, 240)
            : model.schedulePeopleColumnWidth
    }
    private var headerHeight: CGFloat { 62 * typeScale }
    private var strongTextColor: Color { colorScheme == .dark ? .white : .black }

    var body: some View {
        VStack(spacing: 0) {
            scheduleToolbar
            Divider().opacity(0.5)

            GeometryReader { proxy in
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 0) {
                        peopleColumn
                            .frame(width: peopleWidth)

                        Divider()
                            .overlay(.separator)

                        timelineColumn(width: max(proxy.size.width - peopleWidth - 1, 1))
                    }
                    .frame(minHeight: proxy.size.height, alignment: .topLeading)
                }
                .scrollIndicators(.visible)
                .contentMargins(
                    .bottom,
                    horizontalSizeClass == .compact ? 88 : 0,
                    for: .scrollContent
                )
            }
        }
        .background(.background)
        .accessibilityIdentifier("people-schedule-view")
        .accessibilityLabel("人员排期，\(rows.count) 人，\(model.scheduleRangeTitle)")
        .accessibilityElement(children: .contain)
    }

    private var scheduleToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Button {
                        model.moveSchedulePeriod(-1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("上一周期")
                    .accessibilityIdentifier("schedule-previous")

                    Button {
                        model.selectScheduleToday()
                    } label: {
                        Label("今天", systemImage: "calendar.badge.clock")
                            .frame(minHeight: 44)
                            .foregroundStyle(strongTextColor)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("今天")
                    .accessibilityIdentifier("schedule-today")

                    Button {
                        model.moveSchedulePeriod(1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("下一周期")
                    .accessibilityIdentifier("schedule-next")
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.scheduleRangeTitle)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                    Text("\(model.filteredTasks.count) 项任务 · \(rows.count) 人")
                        .font(.caption)
                        .foregroundStyle(strongTextColor)
                }
                .frame(minWidth: 190, alignment: .leading)
                .accessibilityElement(children: .combine)

                Picker("周期", selection: Binding(
                    get: { model.schedulePeriod },
                    set: { model.setSchedulePeriod($0) }
                )) {
                    ForEach(SchedulePeriod.allCases) { period in
                        Text(period.title).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 132)
                .accessibilityIdentifier("schedule-period")

                Picker("密度", selection: $model.scheduleDensity) {
                    ForEach(ScheduleDensity.allCases) { density in
                        Text(density.title).tag(density)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)
                .accessibilityLabel("显示密度")
                .accessibilityIdentifier("schedule-density")

                Button {
                    isShowingSettings.toggle()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("排期布局设置")
                .accessibilityIdentifier("schedule-settings")
                .popover(isPresented: $isShowingSettings, arrowEdge: .bottom) {
                    PeopleScheduleSettingsPopover(model: model)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .frame(minHeight: 64)
    }

    private var peopleColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "person.3.sequence.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("人员")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(strongTextColor)
                Spacer()
                Text("\(rows.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(strongTextColor)
            }
            .padding(.horizontal, 14)
            .frame(height: headerHeight)
            .background(.background)

            ForEach(rows) { row in
                PeopleSchedulePersonHeader(
                    model: model,
                    row: row,
                    height: rowHeight(for: row),
                    laneHeight: laneHeight
                )
                Divider().opacity(0.5)
            }
        }
        .background(.background)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(.separator)
                .frame(width: 1)
                .accessibilityHidden(true)
        }
    }

    private func timelineColumn(width: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 0) {
                    PeopleScheduleDateHeader(
                        days: model.scheduleDays,
                        model: model,
                        dateWidth: dateWidth,
                        height: headerHeight,
                        horizontalOffset: horizontalOffset,
                        viewportWidth: width
                    )

                    ForEach(rows) { row in
                        PeopleScheduleTimelineRow(
                            model: model,
                            row: row,
                            days: model.scheduleDays,
                            dateWidth: dateWidth,
                            height: rowHeight(for: row),
                            laneHeight: laneHeight,
                            horizontalOffset: horizontalOffset,
                            viewportWidth: width,
                            scrollProxy: proxy,
                            scrollToDay: scrollToDay
                        )
                        Divider().opacity(0.5)
                    }
                }
                .frame(width: CGFloat(model.scheduleDays.count) * dateWidth, alignment: .leading)
            }
            .scrollIndicators(.visible)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.x + geometry.contentInsets.leading
            } action: { _, value in
                let clamped = max(0, value)
                if abs(horizontalOffset - clamped) > 0.5 {
                    horizontalOffset = clamped
                }
                guard hasRestoredScroll else { return }
                let dayIndex = min(
                    Int(clamped / max(dateWidth, 1)),
                    max(model.scheduleDays.count - 1, 0)
                )
                if model.scheduleDays.indices.contains(dayIndex) {
                    model.setScheduleScrollAnchor(model.scheduleDays[dayIndex])
                }
            }
            .onAppear {
                viewportWidth = width
                Swift.Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(80))
                    scrollToStoredAnchor(proxy, animated: false)
                    try? await Task.sleep(for: .milliseconds(80))
                    hasRestoredScroll = true
                }
            }
            .onChange(of: width) { _, newValue in
                viewportWidth = newValue
            }
            .onChange(of: model.scheduleRangeStart) { _, _ in
                scrollToDay(model.scheduleRangeStart, proxy, animated: false)
            }
            .onChange(of: model.selectedDate) { _, date in
                guard date >= model.scheduleRangeStart, date <= model.scheduleRangeEnd else { return }
                scrollToDay(date, proxy, animated: !reduceMotion)
            }
        }
    }

    private var laneHeight: CGFloat {
        let base: CGFloat = switch model.scheduleDensity {
        case .compact: 50
        case .standard: 58
        case .comfortable: 66
        }
        return base * typeScale
    }

    private var typeScale: CGFloat {
        switch dynamicTypeSize {
        case .xSmall: 0.86
        case .small: 0.92
        case .medium: 0.97
        case .large: 1
        case .xLarge: 1.08
        case .xxLarge: 1.16
        case .xxxLarge: 1.26
        case .accessibility1: 1.4
        case .accessibility2: 1.54
        case .accessibility3: 1.68
        case .accessibility4: 1.82
        case .accessibility5: 1.96
        @unknown default: 1
        }
    }

    private func rowHeight(for row: PeopleScheduleRow) -> CGFloat {
        if model.collapsedSchedulePersonIDs.contains(row.id) {
            return 58 * typeScale
        }
        return max(64, CGFloat(max(row.laneCount, 1)) * laneHeight + 12)
    }

    private func makeRow(id: String, person: Person?, tasks: [TaskItem]) -> PeopleScheduleRow {
        let slices = PeopleScheduleLayout.slices(
            for: tasks,
            days: model.scheduleDays,
            calendar: model.projectCalendar
        )
        let visibleTasks = Dictionary(grouping: slices, by: \.task.id).compactMap { $0.value.first?.task }
        return PeopleScheduleRow(
            id: id,
            person: person,
            tasks: visibleTasks,
            slices: slices,
            laneCount: PeopleScheduleLayout.laneCount(for: slices)
        )
    }

    private func scrollToStoredAnchor(_ proxy: ScrollViewProxy, animated: Bool) {
        let anchorID = model.scheduleScrollAnchorDayID ?? model.selectedDateString
        guard let date = KshiftDate.date(from: anchorID, calendar: model.projectCalendar) else {
            scrollToDay(model.selectedDate, proxy, animated: animated)
            return
        }
        scrollToDay(date, proxy, animated: animated)
    }

    private func scrollToDay(_ date: Date, _ proxy: ScrollViewProxy, animated: Bool) {
        let id = KshiftDate.isoString(from: date, calendar: model.projectCalendar)
        guard model.scheduleDays.contains(where: {
            KshiftDate.isoString(from: $0, calendar: model.projectCalendar) == id
        }) else { return }
        if animated {
            withAnimation(.snappy(duration: 0.25)) {
                proxy.scrollTo(id, anchor: .leading)
            }
        } else {
            proxy.scrollTo(id, anchor: .leading)
        }
    }
}

private struct PeopleScheduleRow: Identifiable {
    let id: String
    let person: Person?
    let tasks: [TaskItem]
    let slices: [PeopleScheduleTaskSlice]
    let laneCount: Int

    var inProgressCount: Int {
        tasks.filter { $0.status == .inProgress }.count
    }

    var urgentCount: Int {
        tasks.filter { $0.priority == .urgent }.count
    }
}

private struct PeopleSchedulePersonHeader: View {
    @ObservedObject var model: AppModel
    let row: PeopleScheduleRow
    let height: CGFloat
    let laneHeight: CGFloat
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    private var strongTextColor: Color { colorScheme == .dark ? .white : .black }

    private var collapsed: Bool {
        model.collapsedSchedulePersonIDs.contains(row.id)
    }

    var body: some View {
        Button {
            model.toggleSchedulePersonCollapsed(row.id)
        } label: {
            HStack(spacing: 9) {
                avatar
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.person?.name ?? "未分配")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(strongTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(collapsed ? "\(row.tasks.count) 项任务" : roleLine)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(strongTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .foregroundStyle(strongTextColor)
        .frame(height: height)
        .background(.background)
        .overlay(alignment: .bottomTrailing) {
            if !collapsed, !row.tasks.isEmpty, !dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 5) {
                    countBadge("\(row.tasks.count)", symbol: "list.bullet", color: .secondary)
                    if row.inProgressCount > 0 {
                        countBadge("\(row.inProgressCount)", symbol: "circle.lefthalf.filled", color: .blue)
                    }
                    if row.urgentCount > 0 {
                        countBadge("\(row.urgentCount)", symbol: "flag.fill", color: .red)
                    }
                }
                .padding(.trailing, 10)
                .padding(.bottom, 5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowAccessibilityLabel)
        .accessibilityValue(collapsed ? "已折叠" : "已展开")
        .accessibilityIdentifier("schedule-person-\(row.id)")
    }

    private var avatar: some View {
        Group {
            if let person = row.person {
                PersonAvatar(person: person, size: 30)
            } else {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
            }
        }
        .accessibilityHidden(true)
    }

    private var roleLine: String {
        let role = row.person?.role.title ?? "无负责人"
        return "\(role) · \(row.tasks.count) 项任务"
    }

    private var rowAccessibilityLabel: String {
        let name = row.person?.name ?? "未分配"
        let role = row.person?.role.title ?? "无负责人"
        return "\(name)，\(role)，\(row.tasks.count) 项任务，\(row.inProgressCount) 项进行中，\(row.urgentCount) 项 P0"
    }

    private func countBadge(_ value: String, symbol: String, color: Color) -> some View {
        Label(value, systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .font(.caption2.monospacedDigit().weight(.semibold))
            .foregroundStyle(strongTextColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.1), in: Capsule())
    }
}

private struct PeopleScheduleDateHeader: View {
    let days: [Date]
    let model: AppModel
    let dateWidth: CGFloat
    let height: CGFloat
    let horizontalOffset: CGFloat
    let viewportWidth: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    private var strongTextColor: Color { colorScheme == .dark ? .white : .black }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.element) { index, day in
                let isToday = model.isProjectToday(day)
                let isSelected = model.projectCalendar.isDate(day, inSameDayAs: model.selectedDate)
                let rawVisibleStart = Int(horizontalOffset / max(dateWidth, 1))
                let fractionalOffset = horizontalOffset.truncatingRemainder(
                    dividingBy: max(dateWidth, 1)
                )
                let visibleStart = rawVisibleStart + (fractionalOffset > 4 ? 1 : 0)
                let visibleCount = max(Int(ceil(viewportWidth / max(dateWidth, 1))), 1)
                let visibleEnd = min(visibleStart + visibleCount - 1, days.count - 1)
                let isFullyVisible = index >= visibleStart && index <= visibleEnd
                Button {
                    model.selectDate(day)
                } label: {
                    VStack(spacing: 3) {
                        Text(day.formatted(
                            Date.FormatStyle(timeZone: model.projectTimeZone).weekday(.narrow)
                        ))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(strongTextColor)
                        Text(day.formatted(
                            Date.FormatStyle(timeZone: model.projectTimeZone).day()
                        ))
                        .font(.callout.monospacedDigit().weight(isToday || isSelected ? .bold : .medium))
                        .foregroundStyle(strongTextColor)
                    }
                    .frame(width: dateWidth, height: height)
                    .background {
                        if isToday {
                            Color.accentColor.opacity(0.12)
                        } else if isSelected {
                            Color.accentColor.opacity(0.06)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if isToday {
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: min(dateWidth - 24, 46), height: 3)
                                .padding(.bottom, 3)
                        }
                    }
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(.separator.opacity(0.7)).frame(width: 0.5)
                    }
                    .contentShape(Rectangle())
                    .accessibilityHidden(true)
                }
                .buttonStyle(.plain)
                .foregroundStyle(strongTextColor)
                .accessibilityElement(children: .ignore)
                .opacity(isFullyVisible ? 1 : 0)
                .id(KshiftDate.isoString(from: day, calendar: model.projectCalendar))
                .accessibilityLabel(dateAccessibilityLabel(day, isToday: isToday, isSelected: isSelected))
                .accessibilityHidden(!isFullyVisible)
            }
        }
        .frame(width: CGFloat(days.count) * dateWidth, height: height, alignment: .leading)
        .background(.background)
    }

    private func dateAccessibilityLabel(_ day: Date, isToday: Bool, isSelected: Bool) -> String {
        var parts = [day.formatted(Date.FormatStyle(timeZone: model.projectTimeZone).month(.wide).day().weekday(.wide))]
        if isToday { parts.append("今天") }
        if isSelected { parts.append("已选择") }
        return parts.joined(separator: "，")
    }
}

private struct PeopleScheduleTimelineRow: View {
    @ObservedObject var model: AppModel
    let row: PeopleScheduleRow
    let days: [Date]
    let dateWidth: CGFloat
    let height: CGFloat
    let laneHeight: CGFloat
    let horizontalOffset: CGFloat
    let viewportWidth: CGFloat
    let scrollProxy: ScrollViewProxy
    let scrollToDay: (Date, ScrollViewProxy, Bool) -> Void

    @Namespace private var glassNamespace

    private var collapsed: Bool {
        model.collapsedSchedulePersonIDs.contains(row.id)
    }

    private var visibleStartIndex: Int {
        min(Int(horizontalOffset / max(dateWidth, 1)), max(days.count - 1, 0))
    }

    private var visibleDayCount: Int {
        max(Int(ceil(viewportWidth / max(dateWidth, 1))), 1)
    }

    private var visibleEndIndex: Int {
        min(visibleStartIndex + visibleDayCount - 1, max(days.count - 1, 0))
    }

    private var markers: [Int: PeopleScheduleTaskSlice] {
        guard !collapsed else { return [:] }
        let values = PeopleScheduleLayout.hiddenSuccessorMarkers(
            in: row.slices,
            visibleStartIndex: visibleStartIndex,
            visibleEndIndex: visibleEndIndex
        )
        return values
    }

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            ZStack(alignment: .topLeading) {
                PeopleScheduleDayGrid(
                    model: model,
                    personID: row.person?.id,
                    days: days,
                    dateWidth: dateWidth,
                    height: height
                )

                if !collapsed {
                    ForEach(row.slices) { slice in
                        PeopleScheduleTaskCapsule(
                            model: model,
                            task: slice.task,
                            slice: slice,
                            dateWidth: dateWidth,
                            laneHeight: laneHeight,
                            horizontalOffset: horizontalOffset,
                            viewportWidth: viewportWidth,
                            scrollProxy: scrollProxy,
                            scrollToDay: scrollToDay
                        )
                        .frame(
                            width: max(CGFloat(slice.dayCount) * dateWidth - 6, 32),
                            height: max(laneHeight - 2, 46)
                        )
                        .offset(
                            x: CGFloat(slice.startIndex) * dateWidth + 3,
                            y: CGFloat(slice.lane) * laneHeight + 3
                        )
                        .glassEffectID(slice.id, in: glassNamespace)
                    }

                    ForEach(markers.keys.sorted(), id: \.self) { lane in
                        if let marker = markers[lane] {
                            PeopleScheduleOverflowMarker(
                                model: model,
                                task: marker.task,
                                scrollProxy: scrollProxy,
                                scrollToDay: scrollToDay
                            )
                            .frame(
                                width: min(max(viewportWidth * 0.34, 260), 380),
                                height: max(laneHeight - 8, 28)
                            )
                            .offset(
                                x: max(horizontalOffset + viewportWidth - min(max(viewportWidth * 0.34, 260), 380) - 10, 6),
                                y: CGFloat(lane) * laneHeight + 4
                            )
                        }
                    }
                }
            }
        }
        .frame(width: CGFloat(days.count) * dateWidth, height: height, alignment: .topLeading)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityLabel((row.person?.name ?? "未分配") + " 的时间轴")
        .accessibilityIdentifier("schedule-row-\(row.id)")
    }
}

private struct PeopleScheduleDayGrid: View {
    @ObservedObject var model: AppModel
    let personID: String?
    let days: [Date]
    let dateWidth: CGFloat
    let height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                let isToday = model.isProjectToday(day)
                let isSelected = model.projectCalendar.isDate(day, inSameDayAs: model.selectedDate)
                Rectangle()
                    .fill(dayBackground(isToday: isToday, isSelected: isSelected))
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(.separator.opacity(0.55)).frame(width: 0.5)
                    }
                    .frame(width: dateWidth, height: height)
                    .dropDestination(for: String.self) { taskIDs, _ in
                        guard let taskID = taskIDs.first else { return false }
                        Swift.Task {
                            await model.moveScheduleTask(
                                taskID: taskID,
                                toAssigneeID: personID,
                                date: day
                            )
                        }
                        return true
                    }
                    .accessibilityHidden(true)
            }
        }
        .frame(width: CGFloat(days.count) * dateWidth, height: height, alignment: .leading)
    }

    private func dayBackground(isToday: Bool, isSelected: Bool) -> Color {
        if isToday { return Color.accentColor.opacity(0.08) }
        if isSelected { return Color.accentColor.opacity(0.035) }
        return Color.clear
    }
}

private struct PeopleScheduleTaskCapsule: View {
    @ObservedObject var model: AppModel
    let task: TaskItem
    let slice: PeopleScheduleTaskSlice
    let dateWidth: CGFloat
    let laneHeight: CGFloat
    let horizontalOffset: CGFloat
    let viewportWidth: CGFloat
    let scrollProxy: ScrollViewProxy
    let scrollToDay: (Date, ScrollViewProxy, Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.kshiftForceReduceTransparency) private var forceReduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isFocused: Bool
    @State private var isHovering = false
    @State private var isStatusHovering = false
    @State private var pinnedStatusPicker = false

    private var taskWidth: CGFloat {
        CGFloat(slice.dayCount) * dateWidth - 6
    }

    private var titleLeading: CGFloat {
        let leading = PeopleScheduleLayout.stickyTitleLeading(
            taskStartIndex: slice.startIndex,
            dateColumnWidth: dateWidth,
            taskWidth: taskWidth,
            horizontalOffset: horizontalOffset,
            viewportWidth: viewportWidth
        )
        return min(leading, max(taskWidth - 44, 8))
    }

    private var palette: SchedulePriorityPalette {
        SchedulePriorityPalette(priority: task.priority)
    }

    private var taskShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
    }

    private var glassTint: Color {
        let opacity = task.status == .done ? 0.06 : (isHovering ? 0.22 : 0.16)
        return palette.glassTint.opacity(opacity)
    }

    private var borderColor: Color {
        if contrast == .increased || isFocused {
            return colorScheme == .dark ? .white : .black
        }
        if isHovering {
            return palette.accent.opacity(0.72)
        }
        return colorScheme == .dark ? .white.opacity(0.20) : .black.opacity(0.12)
    }

    private var dateLabel: String {
        if slice.task.scheduleStartDate == slice.task.scheduleEndDate {
            return slice.task.scheduleEndDate
        }
        return "\(slice.task.scheduleStartDate) 至 \(slice.task.scheduleEndDate)"
    }

    var body: some View {
        GeometryReader { geometry in
            taskSurface {
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(palette.accent.opacity(task.status == .done ? 0.42 : 1))
                        .frame(width: 3, height: max(geometry.size.height - 18, 18))
                        .offset(x: 9)

                    Text(task.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .allowsTightening(true)
                        .frame(maxWidth: max(geometry.size.width - 56, 20), alignment: .leading)
                        .offset(x: max(titleLeading, 19))
                        .accessibilityHidden(true)

                    Button {
                        pinnedStatusPicker.toggle()
                    } label: {
                        Image(systemName: task.status.symbol)
                            .font(.system(size: 12, weight: .bold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(task.status.tint)
                            .frame(width: 22, height: 22)
                            .frame(width: 44, height: max(laneHeight - 4, 44))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .onHover { hovering in
                        isStatusHovering = hovering
                    }
                    .accessibilityLabel("\(task.title)，状态 \(task.status.title)。展开状态选择")
                    .accessibilityIdentifier("schedule-status-\(task.id)")

                    resizeHandle(edge: .start)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    resizeHandle(edge: .end)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .contentShape(taskShape)
        .onHover { isHovering = $0 }
        .popover(
            isPresented: Binding(
                get: { isStatusHovering || pinnedStatusPicker },
                set: { presented in
                    if !presented { pinnedStatusPicker = false }
                }
            ),
            arrowEdge: .bottom
        ) {
            PeopleScheduleStatusPicker(model: model, task: task)
        }
        .onTapGesture {
            model.presentDetails(task)
        }
        .draggable(task.id)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .help("\(task.title)\n\(task.priority.code) · \(task.status.title) · \(dateLabel)")
        .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: isHovering)
        .opacity(task.status == .done ? 0.72 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(task.title)，\(task.priority.code)，\(task.status.title)，\(dateLabel)")
        .accessibilityHint("拖动可移动任务。点击可查看详情。")
        .accessibilityAction(named: "查看任务详情") {
            model.presentDetails(task)
        }
        .accessibilityIdentifier("schedule-task-\(task.id)")
    }

    @ViewBuilder
    private func taskSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let content = content()
        if reduceTransparency || forceReduceTransparency {
            content
                .background(.background, in: taskShape)
                .overlay {
                    taskShape.strokeBorder(borderColor, lineWidth: contrast == .increased ? 2 : 1)
                }
        } else {
            content
                .glassEffect(.regular.tint(glassTint).interactive(), in: taskShape)
                .overlay {
                    taskShape.strokeBorder(
                        borderColor,
                        lineWidth: contrast == .increased || isFocused ? 2 : 1
                    )
                }
        }
    }

    private func resizeHandle(edge: ScheduleResizeEdge) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 12)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onEnded { value in
                        let dayDelta = Int((value.translation.width / max(dateWidth, 1)).rounded())
                        guard dayDelta != 0 else { return }
                        let startDate = KshiftDate.date(
                            from: task.scheduleStartDate,
                            calendar: model.projectCalendar
                        ) ?? model.selectedDate
                        let endDate = KshiftDate.date(
                            from: task.scheduleEndDate,
                            calendar: model.projectCalendar
                        ) ?? startDate
                        let target = edge == .start ? startDate : endDate
                        let adjusted = KshiftDate.addingDays(
                            dayDelta,
                            to: target,
                            calendar: model.projectCalendar
                        )
                        Swift.Task {
                            await model.resizeScheduleTask(taskID: task.id, edge: edge, date: adjusted)
                        }
                    }
            )
            .accessibilityHidden(true)
    }
}

private struct PeopleScheduleStatusPicker: View {
    @ObservedObject var model: AppModel
    let task: TaskItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(task.title)
                .font(.callout.weight(.semibold))
                .lineLimit(2)
            Text("更改状态")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(TaskStatus.allCases) { status in
                    Button {
                        Swift.Task { await model.setStatus(task, to: status) }
                    } label: {
                        Image(systemName: status.symbol)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glass)
                    .tint(status.tint)
                    .help(status.title)
                    .accessibilityLabel(status.title)
                    .accessibilityIdentifier("schedule-status-\(status.rawValue)-\(task.id)")
                }
            }
        }
        .padding(14)
        .frame(minWidth: 250)
    }
}

private struct PeopleScheduleOverflowMarker: View {
    @ObservedObject var model: AppModel
    let task: TaskItem
    let scrollProxy: ScrollViewProxy
    let scrollToDay: (Date, ScrollViewProxy, Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShowingPreview = false

    var body: some View {
        Button {
            locateTask()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "signpost.right.fill")
                    .accessibilityHidden(true)
                Text("更多：\(task.title)")
                    .lineLimit(1)
                Spacer(minLength: 2)
                Image(systemName: "arrow.right")
                    .accessibilityHidden(true)
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background(.background.opacity(0.96), in: Capsule())
        .overlay {
            Capsule().strokeBorder(.separator, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
        .onHover { isShowingPreview = $0 }
        .popover(isPresented: $isShowingPreview, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text(task.title)
                    .font(.headline)
                Text("\(task.priority.code) · \(task.status.title)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(task.priority.tint)
                Text("\(task.scheduleStartDate) 至 \(task.scheduleEndDate)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("点击路标可切换到目标任务。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(minWidth: 260, maxWidth: 380, alignment: .leading)
        }
        .accessibilityLabel("更多任务：\(task.title)，\(task.priority.code)，\(task.status.title)")
        .accessibilityHint("点击定位目标任务")
        .accessibilityIdentifier("schedule-marker-\(task.id)")
    }

    private func locateTask() {
        model.focusSchedule(on: task)
        guard let date = KshiftDate.date(
            from: task.scheduleStartDate,
            calendar: model.projectCalendar
        ) else { return }
        scrollToDay(date, scrollProxy, !reduceMotion)
    }
}

private struct PeopleScheduleSettingsPopover: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("排期布局")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Label("人员列宽度 \(Int(model.schedulePeopleColumnWidth))pt", systemImage: "person.2")
                    .font(.caption.weight(.semibold))
                Slider(
                    value: Binding(
                        get: { Double(model.schedulePeopleColumnWidth) },
                        set: { model.setSchedulePeopleColumnWidth(CGFloat($0)) }
                    ),
                    in: 168...320,
                    step: 4
                )
                .accessibilityLabel("人员列宽度")
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("日期列宽度 \(Int(model.scheduleDateColumnWidth))pt", systemImage: "calendar")
                    .font(.caption.weight(.semibold))
                Slider(
                    value: Binding(
                        get: { Double(model.scheduleDateColumnWidth) },
                        set: { model.setScheduleDateColumnWidth(CGFloat($0)) }
                    ),
                    in: 96...360,
                    step: 8
                )
                .accessibilityLabel("日期列宽度")
            }

            Picker("显示密度", selection: $model.scheduleDensity) {
                ForEach(ScheduleDensity.allCases) { density in
                    Text(density.title).tag(density)
                }
            }
            .pickerStyle(.segmented)

            Text("布局设置按项目保存。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 330)
    }
}

private struct SchedulePriorityPalette {
    let priority: TaskPriority

    var accent: Color {
        switch priority {
        case .urgent: Color(hex: "#C62828")
        case .high: Color(hex: "#B26A00")
        case .medium: Color(hex: "#1565C0")
        case .low: Color(hex: "#666A70")
        }
    }

    var glassTint: Color {
        switch priority {
        case .urgent: .red
        case .high: .yellow
        case .medium: .blue
        case .low: .gray
        }
    }
}
