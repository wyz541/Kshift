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
    @State private var isShowingFilters = false
    @State private var hasRestoredScroll = false
    @State private var weekScrollPosition: String?

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
    private var isAccessibilityTextSize: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        VStack(spacing: 0) {
            scheduleToolbar
            Divider().opacity(0.5)

            if horizontalSizeClass == .compact {
                compactSchedule
            } else {
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
                }
            }
        }
        .background(.background)
        // Establish the container first so the identifier and label describe
        // the container itself instead of propagating onto every child control.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("people-schedule-view")
        .accessibilityLabel("人员排期，\(rows.count) 人，\(model.scheduleRangeTitle)")
    }

    private var compactSchedule: some View {
        VStack(spacing: 0) {
            compactWeekStrip
                .padding(.horizontal, 12)

            Divider().opacity(0.4)

            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    compactTaskSummary

                    ForEach(rows) { row in
                        CompactSchedulePersonSection(model: model, row: row)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 88)
            }
            .scrollIndicators(.visible)
            .accessibilityLabel("人员排期，\(rows.count) 人，\(model.scheduleRangeTitle)")
        }
    }

    /// Counts tasks inside the shown range, so the number matches the week
    /// strip. A task with several assignees appears in several rows but
    /// counts once.
    private var compactTaskSummary: some View {
        let visibleTaskCount = Set(rows.flatMap { $0.tasks.map(\.id) }).count
        return Text("\(visibleTaskCount) 项任务 · \(rows.count) 人")
            .font(.caption.weight(.medium))
            .foregroundStyle(strongTextColor)
            .accessibilityIdentifier("schedule-task-summary")
    }

    /// Weeks that have tasks, plus the current and selected weeks.
    private var compactWeekBuckets: [PeopleScheduleWeekBucket] {
        PeopleScheduleLayout.weekBuckets(
            for: model.filteredTasks,
            alwaysInclude: [model.projectToday, model.selectedDate],
            calendar: model.projectCalendar
        )
    }

    /// The selected chip exists only in week scope. Month scope shows a whole
    /// month, so no single week is selected there.
    private var compactSelectedWeekStart: Date? {
        guard model.schedulePeriod == .week else { return nil }
        return model.scheduleRangeStart
    }

    private var compactSelectedWeekID: String? {
        compactSelectedWeekStart.map { weekBucketID($0) }
    }

    private func weekBucketID(_ date: Date) -> String {
        KshiftDate.isoString(from: date, calendar: model.projectCalendar)
    }

    private var compactWeekChipWidth: CGFloat? { isAccessibilityTextSize ? 280 : nil }

    /// Week-level quick filter. Each chip is one week that has tasks; tapping
    /// it shows that week. The strip scrolls horizontally and keeps the
    /// selected week in view.
    private var compactWeekStrip: some View {
        let buckets = compactWeekBuckets
        let selectedWeekID = compactSelectedWeekID
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 6) {
                ForEach(buckets) { bucket in
                    compactWeekChip(
                        bucket,
                        isSelected: weekBucketID(bucket.start) == selectedWeekID
                    )
                    .id(weekBucketID(bucket.start))
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 2)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $weekScrollPosition, anchor: .leading)
        .onAppear {
            weekScrollPosition = selectedWeekID
        }
        .onChange(of: selectedWeekID) { _, newValue in
            weekScrollPosition = newValue
        }
        .onChange(of: isAccessibilityTextSize) { _, _ in
            weekScrollPosition = selectedWeekID
        }
        // A horizontal scroll view is vertically flexible; fix it to the chip
        // height so the chips can still grow with Dynamic Type.
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 4)
        .background(.background)
        .accessibilityIdentifier("schedule-week-strip")
    }

    private func compactWeekChip(_ bucket: PeopleScheduleWeekBucket, isSelected: Bool) -> some View {
        let isCurrentWeek = bucket.contains(model.projectToday)
        return Button {
            selectWeek(bucket)
        } label: {
            VStack(spacing: 1) {
                Text(weekRangeLabel(bucket))
                    .font(.footnote.monospacedDigit().weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(weekDetailLabel(bucket, isCurrentWeek: isCurrentWeek))
                    .font(.caption.weight(isCurrentWeek ? .bold : .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            // Text keeps the strong color in every state; the selected week is
            // marked by the tinted fill and accent border, which keeps text
            // contrast independent of the accent color.
            .foregroundStyle(strongTextColor)
            .lineLimit(isAccessibilityTextSize ? 2 : 1)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(width: compactWeekChipWidth)
            .clipped()
            .frame(minHeight: 44)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.separator),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: compactWeekChipWidth)
        .accessibilityLabel(weekAccessibilityLabel(bucket, isCurrentWeek: isCurrentWeek, isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(
            "schedule-week-\(KshiftDate.isoString(from: bucket.start, calendar: model.projectCalendar))"
        )
    }

    /// Shows the tapped week. Month scope switches to week scope, so a chip
    /// tap always narrows the list to one week. Inside the current week the
    /// selection stays on today; other weeks select their first day.
    private func selectWeek(_ bucket: PeopleScheduleWeekBucket) {
        model.setSchedulePeriod(.week)
        let today = model.projectToday
        model.selectDate(bucket.contains(today) ? today : bucket.start)
    }

    private func weekRangeLabel(_ bucket: PeopleScheduleWeekBucket) -> String {
        let calendar = model.projectCalendar
        let startMonth = calendar.component(.month, from: bucket.start)
        let startDay = calendar.component(.day, from: bucket.start)
        let endMonth = calendar.component(.month, from: bucket.end)
        let endDay = calendar.component(.day, from: bucket.end)
        if startMonth == endMonth {
            return "\(startMonth)/\(startDay)–\(endDay)"
        }
        return "\(startMonth)/\(startDay)–\(endMonth)/\(endDay)"
    }

    private func weekDetailLabel(_ bucket: PeopleScheduleWeekBucket, isCurrentWeek: Bool) -> String {
        let count = bucket.taskCount == 0 ? "无任务" : "\(bucket.taskCount) 项"
        return isCurrentWeek ? "本周 · \(count)" : count
    }

    private func weekAccessibilityLabel(
        _ bucket: PeopleScheduleWeekBucket,
        isCurrentWeek: Bool,
        isSelected: Bool
    ) -> String {
        let style = Date.FormatStyle(timeZone: model.projectTimeZone).month(.wide).day()
        var parts = [
            "\(bucket.start.formatted(style)) 至 \(bucket.end.formatted(style))",
            bucket.taskCount == 0 ? "无任务" : "\(bucket.taskCount) 项任务",
        ]
        if isCurrentWeek { parts.append("本周") }
        if isSelected { parts.append("已选择") }
        return parts.joined(separator: "，")
    }

    @ViewBuilder
    private var scheduleToolbar: some View {
        if horizontalSizeClass == .compact {
            compactScheduleToolbar
        } else {
            regularScheduleToolbar
        }
    }

    /// Compact chrome: one row. Period navigation on the left, the two
    /// selection controls in the middle, and an overflow menu for the
    /// low-frequency actions. Nine controls cannot share one phone-width row
    /// without truncation, so the menu absorbs the rest.
    private var compactScheduleToolbar: some View {
        HStack(spacing: 6) {
            compactStepButton(
                symbol: "chevron.left",
                label: "上一周期",
                identifier: "schedule-previous"
            ) {
                model.moveSchedulePeriod(-1)
            }

            compactTodayControl

            compactStepButton(
                symbol: "chevron.right",
                label: "下一周期",
                identifier: "schedule-next"
            ) {
                model.moveSchedulePeriod(1)
            }

            Spacer(minLength: 4)

            sortControl

            filterControl

            compactOverflowMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(minHeight: 52)
    }

    private var compactTodayControl: some View {
        Button {
            model.selectScheduleToday()
        } label: {
            if isAccessibilityTextSize {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 30, height: 30)
            } else {
                Label("今天", systemImage: "calendar.badge.clock")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(minHeight: 34)
                    .foregroundStyle(strongTextColor)
            }
        }
        .buttonStyle(KshiftCompactGlassButtonStyle())
        .accessibilityLabel("今天")
        .accessibilityIdentifier("schedule-today")
    }

    private var sortControl: some View {
        Menu {
            ForEach(TaskSortOption.allCases) { option in
                Toggle(option.title, isOn: Binding(
                    get: { model.sortOption == option },
                    set: { isSelected in
                        if isSelected { model.sortOption = option }
                    }
                ))
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 30, height: 30)
        }
        .menuStyle(.button)
        .buttonStyle(KshiftCompactGlassButtonStyle())
        .accessibilityLabel("排序")
        .accessibilityIdentifier("sort-menu")
    }

    private var filterControl: some View {
        Button {
            isShowingFilters.toggle()
        } label: {
            Image(systemName: model.filter.isActive
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease.circle")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(KshiftCompactGlassButtonStyle())
        .accessibilityLabel("筛选任务")
        .accessibilityIdentifier("filter-button")
        .popover(isPresented: $isShowingFilters, arrowEdge: .bottom) {
            FilterPopover(model: model)
        }
    }

    /// Holds the actions that do not need a permanent slot: period scope,
    /// snapshot refresh, and layout settings.
    private var compactOverflowMenu: some View {
        Menu {
            Picker("周期", selection: Binding(
                get: { model.schedulePeriod },
                set: { model.setSchedulePeriod($0) }
            )) {
                ForEach(SchedulePeriod.allCases) { period in
                    Text(period.title).tag(period)
                }
            }

            Button {
                Swift.Task { await model.refresh() }
            } label: {
                Label("刷新共享快照", systemImage: "arrow.clockwise")
            }
            .accessibilityIdentifier("refresh-button")

            Button {
                isShowingSettings = true
            } label: {
                Label("排期布局设置", systemImage: "slider.horizontal.3")
            }
            .accessibilityIdentifier("schedule-settings")
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 30, height: 30)
        }
        .menuStyle(.button)
        .buttonStyle(KshiftCompactGlassButtonStyle())
        .accessibilityLabel("更多操作")
        .accessibilityIdentifier("schedule-overflow")
        .popover(isPresented: $isShowingSettings, arrowEdge: .bottom) {
            PeopleScheduleSettingsPopover(model: model)
        }
    }

    private func compactStepButton(
        symbol: String,
        label: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(KshiftCompactGlassButtonStyle())
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private var regularScheduleToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    compactStepButton(
                        symbol: "chevron.left",
                        label: "上一周期",
                        identifier: "schedule-previous"
                    ) {
                        model.moveSchedulePeriod(-1)
                    }

                    Button {
                        model.selectScheduleToday()
                    } label: {
                        Label("今天", systemImage: "calendar.badge.clock")
                            .frame(minHeight: 34)
                            .foregroundStyle(strongTextColor)
                    }
                    .buttonStyle(KshiftCompactGlassButtonStyle())
                    .accessibilityLabel("今天")
                    .accessibilityIdentifier("schedule-today")

                    compactStepButton(
                        symbol: "chevron.right",
                        label: "下一周期",
                        identifier: "schedule-next"
                    ) {
                        model.moveSchedulePeriod(1)
                    }
                }

                if horizontalSizeClass == .regular {
                    DatePicker(
                        "选择日期",
                        selection: Binding(
                            get: { model.selectedDate },
                            set: { model.selectDate($0) }
                        ),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .environment(\.timeZone, model.projectTimeZone)
                    .fixedSize()
                    .accessibilityLabel("选择日期")
                    .accessibilityIdentifier("schedule-date-picker")
                }

                Text("\(model.filteredTasks.count) 项任务 · \(rows.count) 人")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(strongTextColor)
                    .lineLimit(1)
                    .frame(minWidth: 108, alignment: .leading)
                    .accessibilityLabel("\(model.filteredTasks.count) 项任务，\(rows.count) 人")

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

                PlannerUtilityControls(model: model)

                Button {
                    isShowingSettings.toggle()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(KshiftCompactGlassButtonStyle())
                .accessibilityLabel("排期布局设置")
                .accessibilityIdentifier("schedule-settings")
                .popover(isPresented: $isShowingSettings, arrowEdge: .bottom) {
                    PeopleScheduleSettingsPopover(model: model)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
        }
        .frame(minHeight: 52)
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
        case .compact: 40
        case .standard: 48
        case .comfortable: 56
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
        return max(56, CGFloat(max(row.laneCount, 1)) * laneHeight + 8)
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

private struct CompactSchedulePersonSection: View {
    @ObservedObject var model: AppModel
    let row: PeopleScheduleRow

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Namespace private var glassNamespace

    private var strongTextColor: Color {
        colorScheme == .dark ? .white : .black
    }
    private var isAccessibilityTextSize: Bool { dynamicTypeSize.isAccessibilitySize }

    private var collapsed: Bool {
        model.collapsedSchedulePersonIDs.contains(row.id)
    }

    private var sortedTasks: [TaskItem] {
        row.tasks.sorted { lhs, rhs in
            if lhs.scheduleStartDate != rhs.scheduleStartDate {
                return lhs.scheduleStartDate < rhs.scheduleStartDate
            }
            return priorityOrder(lhs.priority) < priorityOrder(rhs.priority)
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            header

            if !collapsed {
                if sortedTasks.isEmpty {
                    Text("本周期暂无任务")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    GlassEffectContainer(spacing: 4) {
                        LazyVStack(spacing: 4) {
                            ForEach(sortedTasks) { task in
                                CompactScheduleTaskCapsule(model: model, task: task)
                                    .glassEffectID(task.id, in: glassNamespace)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.separator.opacity(0.6), lineWidth: 1)
        }
        .dropDestination(for: String.self) { taskIDs, _ in
            guard let taskID = taskIDs.first,
                  let task = model.filteredTasks.first(where: { $0.id == taskID }),
                  let date = KshiftDate.date(
                      from: task.scheduleStartDate,
                      calendar: model.projectCalendar
                  )
            else {
                return false
            }
            Swift.Task {
                await model.moveScheduleTask(
                    taskID: taskID,
                    toAssigneeID: row.person?.id,
                    date: date
                )
            }
            return true
        }
    }

    private var header: some View {
        Button {
            model.toggleSchedulePersonCollapsed(row.id)
        } label: {
            Group {
                if isAccessibilityTextSize {
                    accessibilityHeader
                } else {
                    standardHeader
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowAccessibilityLabel)
        .accessibilityValue(collapsed ? "已折叠" : "已展开")
        .accessibilityIdentifier("schedule-person-\(row.id)")
    }

    private var accessibilityHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                avatar

                Text(row.person?.name ?? "未分配")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(strongTextColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(strongTextColor)
                    .fixedSize()
            }

            personSummary
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var standardHeader: some View {
        HStack(spacing: 8) {
            avatar

            VStack(alignment: .leading, spacing: 1) {
                Text(row.person?.name ?? "未分配")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(strongTextColor)
                    .fixedSize(horizontal: false, vertical: true)
                personSummary
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 4)

            Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(strongTextColor)
                .fixedSize()
        }
        .frame(minHeight: 36)
    }

    @ViewBuilder
    private var personSummary: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 3) {
                Text(personAndTaskCount)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(strongTextColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !collapsed {
                    VStack(alignment: .leading, spacing: 2) {
                        if row.inProgressCount > 0 {
                            compactCountBadge(row.inProgressCount, label: "进行中")
                        }
                        if row.urgentCount > 0 {
                            compactCountBadge(row.urgentCount, label: "P0")
                        }
                    }
                }
            }
        } else {
            HStack(spacing: 6) {
                Text(personAndTaskCount)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(strongTextColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)

                Spacer(minLength: 2)

                if !collapsed {
                    if row.inProgressCount > 0 {
                        compactCountBadge(row.inProgressCount, label: "进行中")
                    }
                    if row.urgentCount > 0 {
                        compactCountBadge(row.urgentCount, label: "P0")
                    }
                }
            }
        }
    }

    private var personAndTaskCount: String {
        "\(row.person?.role.title ?? "无负责人") · \(row.tasks.count) 项任务"
    }

    private var avatar: some View {
        Group {
            if let person = row.person {
                PersonAvatar(person: person, size: 26)
            } else {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.body)
                    .foregroundStyle(strongTextColor)
                    .frame(width: 26, height: 26)
            }
        }
        .accessibilityHidden(true)
    }

    private var rowAccessibilityLabel: String {
        let name = row.person?.name ?? "未分配"
        let role = row.person?.role.title ?? "无负责人"
        return "\(name)，\(role)，\(row.tasks.count) 项任务，\(row.inProgressCount) 项进行中，\(row.urgentCount) 项 P0"
    }

    private func compactCountBadge(_ value: Int, label: String) -> some View {
        Text("\(value) \(label)")
            .font(.caption2.monospacedDigit().weight(.semibold))
            .foregroundStyle(strongTextColor)
            .fixedSize()
            .accessibilityHidden(true)
    }

    private func priorityOrder(_ priority: TaskPriority) -> Int {
        switch priority {
        case .urgent: 0
        case .high: 1
        case .medium: 2
        case .low: 3
        }
    }
}

private struct CompactScheduleTaskCapsule: View {
    @ObservedObject var model: AppModel
    let task: TaskItem

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var editDraft: TaskDraft?

    private var isAccessibilityTextSize: Bool { dynamicTypeSize.isAccessibilitySize }
    private var visualHeight: CGFloat {
        isAccessibilityTextSize ? 132 : ScheduleTaskMetrics.visualHeight
    }
    private var hitHeight: CGFloat {
        isAccessibilityTextSize ? max(visualHeight + 8, ScheduleTaskMetrics.hitHeight) : ScheduleTaskMetrics.hitHeight
    }

    private var palette: SchedulePriorityPalette {
        SchedulePriorityPalette(priority: task.priority)
    }

    private var taskShape: Capsule {
        Capsule(style: .continuous)
    }

    private var glassTint: Color {
        palette.fill.opacity(colorScheme == .dark ? 0.45 : 0.28)
    }

    private var dateLabel: String {
        let start = task.scheduleStartDate.split(separator: "-")
        let end = task.scheduleEndDate.split(separator: "-")
        guard start.count == 3, end.count == 3 else {
            return task.scheduleStartDate
        }
        if start == end {
            return "\(start[1])/\(start[2])"
        }
        if start[1] == end[1] {
            return "\(start[1])/\(start[2])–\(end[2])"
        }
        return "\(start[1])/\(start[2])–\(end[1])/\(end[2])"
    }

    /// Canvas text has no intrinsic size, so the frame follows the label
    /// length instead of reserving the widest possible range.
    private var dateWidth: CGFloat {
        CGFloat(dateLabel.count) * ScheduleTaskMetrics.dateCharacterWidth + 4
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Button {
                editDraft = model.editDraft(for: task)
            } label: {
                taskButtonContent
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .frame(height: visualHeight)
            .glassEffect(
                .regular.tint(glassTint).interactive(),
                in: taskShape
            )
            .frame(height: hitHeight)
            .contentShape(Rectangle())
            .accessibilityLabel("\(task.title)，\(task.priority.code)，\(task.status.title)，\(dateLabel)")
            .accessibilityHint("编辑任务")
            .accessibilityIdentifier("schedule-task-\(task.id)")
            .modifier(ScheduleTaskHoverPreviewModifier(model: model, task: task, isEditing: editDraft != nil))
            .contextMenu {
                Button("查看历史和详情") { model.presentDetails(task) }
            }
            .draggable(task.id)
        }
        .overlay(alignment: .leading) {
            statusMenu
        }
        .contentShape(Rectangle())
        .taskEditorPopover(model: model, draft: $editDraft)
    }

    @ViewBuilder
    private var taskButtonContent: some View {
        if isAccessibilityTextSize {
            HStack(alignment: .center, spacing: 6) {
                statusBadge

                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(dateLabel)
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
            }
            .padding(.leading, ScheduleTaskMetrics.statusLeadingInset)
            .padding(.trailing, ScheduleTaskMetrics.trailingInset)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: visualHeight, alignment: .leading)
            .clipShape(taskShape)
            .contentShape(Rectangle())
        } else {
            HStack(spacing: ScheduleTaskMetrics.contentSpacing) {
                statusBadge

                Text(task.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.88)
                    .allowsTightening(true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
                    .accessibilityHidden(true)

                Canvas { context, size in
                    context.draw(
                        Text(dateLabel)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary),
                        at: CGPoint(x: size.width / 2, y: size.height / 2),
                        anchor: .center
                    )
                }
                .frame(width: dateWidth, height: 18)
                .padding(.leading, ScheduleTaskMetrics.titleSpacing)
                .accessibilityHidden(true)
            }
            .padding(.leading, ScheduleTaskMetrics.statusLeadingInset)
            .padding(.trailing, ScheduleTaskMetrics.trailingInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: ScheduleTaskMetrics.visualHeight)
            .clipShape(taskShape)
            .contentShape(Rectangle())
        }
    }

    private var statusMenu: some View {
        Menu {
            ForEach(TaskStatus.allCases) { status in
                Button {
                    Swift.Task { await model.setStatus(task, to: status) }
                } label: {
                    Label(status.title, systemImage: status.symbol)
                }
            }
        } label: {
            Color.clear
                .frame(width: ScheduleTaskMetrics.hitHeight, height: ScheduleTaskMetrics.hitHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(width: ScheduleTaskMetrics.hitHeight, height: ScheduleTaskMetrics.hitHeight)
        .fixedSize(horizontal: true, vertical: true)
        .contentShape(Rectangle())
        .accessibilityLabel("\(task.title)，\(task.priority.code)，状态 \(task.status.title)。更改状态")
        .accessibilityIdentifier("schedule-status-\(task.id)")
    }

    private var statusBadge: some View {
        ScheduleTaskStatusBadge(status: task.status)
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
            HStack(spacing: 8) {
                avatar
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(row.person?.name ?? "未分配")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(strongTextColor)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(1)

                        Spacer(minLength: 0)

                        Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(strongTextColor)
                            .fixedSize()
                    }

                    HStack(spacing: 6) {
                        Text(detailLine)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(strongTextColor)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(1)

                        Spacer(minLength: 0)

                        if shouldShowMetrics {
                            metrics
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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

    private var shouldShowMetrics: Bool {
        !collapsed && !dynamicTypeSize.isAccessibilitySize
    }

    private var detailLine: String {
        let role = row.person?.role.title ?? "无负责人"
        if collapsed || dynamicTypeSize.isAccessibilitySize {
            return "\(role) · \(row.tasks.count) 项任务"
        }
        return role
    }

    private var metrics: some View {
        HStack(spacing: 4) {
            countBadge("\(row.tasks.count)", symbol: "list.bullet")
            if row.inProgressCount > 0 {
                countBadge("\(row.inProgressCount)", symbol: "circle.lefthalf.filled")
            }
            if row.urgentCount > 0 {
                countBadge("\(row.urgentCount)", symbol: "flag.fill")
            }
        }
    }

    private var rowAccessibilityLabel: String {
        let name = row.person?.name ?? "未分配"
        let role = row.person?.role.title ?? "无负责人"
        return "\(name)，\(role)，\(row.tasks.count) 项任务，\(row.inProgressCount) 项进行中，\(row.urgentCount) 项 P0"
    }

    private func countBadge(_ value: String, symbol: String) -> some View {
        Label(value, systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .font(.caption2.monospacedDigit().weight(.semibold))
            .foregroundStyle(strongTextColor)
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
                            Date.FormatStyle(timeZone: model.projectTimeZone).weekday(.abbreviated)
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
        GlassEffectContainer(spacing: 4) {
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
                            width: max(
                                CGFloat(slice.dayCount) * dateWidth - ScheduleTaskMetrics.horizontalInset * 2,
                                32
                            ),
                            height: ScheduleTaskMetrics.visualHeight
                        )
                        .offset(
                            x: CGFloat(slice.startIndex) * dateWidth + ScheduleTaskMetrics.horizontalInset,
                            y: CGFloat(slice.lane) * laneHeight + 2
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
                                height: max(laneHeight - 10, 26)
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
                PeopleScheduleBlankDayCell(
                    model: model,
                    personID: personID,
                    day: day,
                    dateWidth: dateWidth,
                    height: height
                )
            }
        }
        .frame(width: CGFloat(days.count) * dateWidth, height: height, alignment: .leading)
    }
}

private struct PeopleScheduleBlankDayCell: View {
    @ObservedObject var model: AppModel
    let personID: String?
    let day: Date
    let dateWidth: CGFloat
    let height: CGFloat

    @State private var draft: TaskDraft?

    var body: some View {
        Rectangle()
            .fill(dayBackground)
            .overlay(alignment: .trailing) {
                Rectangle().fill(.separator.opacity(0.55)).frame(width: 0.5)
            }
            .frame(width: dateWidth, height: height)
            .contentShape(Rectangle())
            .onTapGesture {
                let assigneeIDs = personID.map { [$0] } ?? []
                draft = model.newTaskDraft(assigneeIDs: assigneeIDs, date: day)
            }
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
            .popover(item: $draft, attachmentAnchor: .rect(.bounds), arrowEdge: .top) { draft in
                TaskEditorView(
                    model: model,
                    initialDraft: draft,
                    presentation: .popover
                )
            }
            .accessibilityHidden(true)
    }

    private var dayBackground: Color {
        if model.isProjectToday(day) {
            return Color.accentColor.opacity(0.08)
        }
        if model.projectCalendar.isDate(day, inSameDayAs: model.selectedDate) {
            return Color.accentColor.opacity(0.035)
        }
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

    @Environment(\.colorScheme) private var colorScheme
    @State private var editDraft: TaskDraft?

    private var taskWidth: CGFloat {
        CGFloat(slice.dayCount) * dateWidth - ScheduleTaskMetrics.horizontalInset * 2
    }

    private var titleLeading: CGFloat {
        let leading = PeopleScheduleLayout.stickyTitleLeading(
            taskStartIndex: slice.startIndex,
            dateColumnWidth: dateWidth,
            taskWidth: taskWidth,
            horizontalOffset: horizontalOffset,
            viewportWidth: viewportWidth
        )
        return min(
            max(leading, ScheduleTaskMetrics.contentLeading),
            max(taskWidth - ScheduleTaskMetrics.trailingInset, 0)
        )
    }

    private var palette: SchedulePriorityPalette {
        SchedulePriorityPalette(priority: task.priority)
    }

    private var taskShape: Capsule {
        Capsule(style: .continuous)
    }

    private var glassTint: Color {
        palette.fill.opacity(colorScheme == .dark ? 0.45 : 0.28)
    }

    private var dateLabel: String {
        if slice.task.scheduleStartDate == slice.task.scheduleEndDate {
            return slice.task.scheduleEndDate
        }
        return "\(slice.task.scheduleStartDate) 至 \(slice.task.scheduleEndDate)"
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Button {
                    editDraft = model.editDraft(for: task)
                } label: {
                    ZStack(alignment: .leading) {
                        statusBadge

                        Text(task.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.78)
                            .allowsTightening(true)
                            .frame(
                                width: PeopleScheduleLayout.clippedTitleWidth(
                                    taskWidth: geometry.size.width,
                                    leadingInset: max(titleLeading, ScheduleTaskMetrics.contentLeading)
                                ),
                                height: geometry.size.height,
                                alignment: .leading
                            )
                            .offset(x: max(titleLeading, ScheduleTaskMetrics.contentLeading))
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .clipShape(taskShape)
                    .contentShape(taskShape)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassEffect(
                    .regular.tint(glassTint).interactive(),
                    in: taskShape
                )
                .contentShape(taskShape)
                .accessibilityLabel("\(task.title)，\(task.priority.code)，\(task.status.title)，\(dateLabel)")
                .accessibilityHint("编辑任务")
                .accessibilityIdentifier("schedule-task-\(task.id)")
                .modifier(ScheduleTaskHoverPreviewModifier(model: model, task: task, isEditing: editDraft != nil))
                .taskEditorPopover(model: model, draft: $editDraft)
                .contextMenu {
                    Button("查看历史和详情") { model.presentDetails(task) }
                }
                .draggable(task.id)
            }
            .overlay(alignment: .leading) {
                statusMenu
            }
            .overlay(alignment: .leading) {
                resizeHandle(edge: .start)
                    .frame(width: 12)
            }
            .overlay(alignment: .trailing) {
                resizeHandle(edge: .end)
                    .frame(width: 12)
            }
        }
        .contentShape(taskShape)
    }

    private var statusMenu: some View {
        Menu {
            ForEach(TaskStatus.allCases) { status in
                Button {
                    Swift.Task { await model.setStatus(task, to: status) }
                } label: {
                    Label(status.title, systemImage: status.symbol)
                }
            }
        } label: {
            Color.clear
                .frame(width: ScheduleTaskMetrics.hitHeight, height: ScheduleTaskMetrics.hitHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(width: ScheduleTaskMetrics.hitHeight, height: ScheduleTaskMetrics.hitHeight)
        .fixedSize(horizontal: true, vertical: true)
        .contentShape(Rectangle())
        .accessibilityLabel("\(task.title)，\(task.priority.code)，状态 \(task.status.title)。更改状态")
        .accessibilityIdentifier("schedule-status-\(task.id)")
    }

    private var statusBadge: some View {
        ScheduleTaskStatusBadge(status: task.status)
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

            ScheduleLayoutSettingsSection(model: model)
        }
        .padding(18)
        .frame(width: 330)
    }
}

private enum ScheduleTaskMetrics {
    static let horizontalInset: CGFloat = 8
    static let visualHeight: CGFloat = 36
    static let hitHeight: CGFloat = 44
    static let statusLeadingInset: CGFloat = 4
    static let contentSpacing: CGFloat = 3
    static let titleSpacing: CGFloat = 6
    /// Advance width of one 10pt semibold monospaced character.
    static let dateCharacterWidth: CGFloat = 6.1
    static let trailingInset: CGFloat = 6
    static let statusFrame: CGFloat = 26
    static let contentLeading: CGFloat = statusFrame + contentSpacing
}

private struct ScheduleTaskStatusBadge: View {
    let status: TaskStatus

    private var symbol: String {
        switch status {
        case .todo: "circle.dashed"
        case .inProgress: "clock.fill"
        case .blocked: "exclamationmark.octagon.fill"
        case .done: "checkmark"
        }
    }

    private var accent: Color {
        switch status {
        case .todo: Color(hex: "#8E8E93")
        case .inProgress: Color(hex: "#0A84FF")
        case .blocked: Color(hex: "#FF453A")
        case .done: Color(hex: "#30D158")
        }
    }

    private var glyph: Color {
        switch status {
        case .todo: Color(hex: "#4B4B50")
        case .inProgress: Color(hex: "#0057C8")
        case .blocked: Color(hex: "#A61B1B")
        case .done: Color(hex: "#0F7A3D")
        }
    }

    var body: some View {
        ZStack {
            Circle().fill(accent)
            Circle()
                .fill(Color.white.opacity(0.96))
                .padding(3)
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .heavy))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(glyph)
        }
        .frame(width: ScheduleTaskMetrics.statusFrame, height: ScheduleTaskMetrics.statusFrame)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct SchedulePriorityPalette {
    let priority: TaskPriority

    var fill: Color {
        switch priority {
        case .urgent: Color(hex: "#D92D3A")
        case .high: Color(hex: "#FFC400")
        case .medium: Color(hex: "#0066FF")
        case .low: Color(hex: "#5F6368")
        }
    }

    var foreground: Color {
        switch priority {
        case .high: .black
        default: .white
        }
    }
}
