import KshiftCore
import SwiftUI

struct CalendarView: View {
    @ObservedObject var model: AppModel
    private var calendar: Calendar { model.projectCalendar }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                monthHeader
                weekdayHeader
                monthGrid
                selectedDaySection
            }
            .padding(20)
        }
        .accessibilityIdentifier("calendar-view")
    }

    private var monthHeader: some View {
        HStack {
            Button {
                shiftMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("上个月")

            Text(monthTitle)
                .font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity)

            Button {
                shiftMonth(1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("下个月")
        }
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private var monthGrid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(0..<leadingBlankCount), id: \.self) { index in
                Color.clear
                    .frame(minHeight: 74)
                    .accessibilityHidden(true)
                    .id("blank-\(index)")
            }
            ForEach(1...daysInMonth, id: \.self) { day in
                dayButton(day: day)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.background)
        )
    }

    private var selectedDaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        model.selectedDate.formatted(
                            Date.FormatStyle(timeZone: calendar.timeZone).month(.wide).day()
                        )
                    )
                        .font(.headline)
                    Text("\(model.selectedDateTasks.count) 项任务")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.presentNewTask(assigneeIDs: [], date: model.selectedDate)
                } label: {
                    Label("添加任务", systemImage: "plus")
                }
                .buttonStyle(.glassProminent)
                .accessibilityIdentifier("calendar-add-task")
            }

            if model.selectedDateTasks.isEmpty {
                Text("这一天没有匹配任务。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(model.selectedDateTasks.sorted(by: calendarTaskSort)) { task in
                    CompactCalendarTask(model: model, task: task)
                    if task.id != model.selectedDateTasks.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.thinMaterial)
        )
    }

    private func dayButton(day: Int) -> some View {
        let date = calendar.date(
            byAdding: .day,
            value: day - 1,
            to: monthStart
        ) ?? monthStart
        let isSelected = calendar.isDate(date, inSameDayAs: model.selectedDate)
        let isToday = model.isProjectToday(date)
        let taskCount = model.taskCount(on: date)

        return Group {
            if isSelected {
                Button {
                    model.selectDate(date)
                } label: {
                    dayLabel(
                        day: day,
                        isSelected: true,
                        isToday: isToday,
                        taskCount: taskCount
                    )
                }
                .buttonStyle(.glassProminent)
            } else {
                Button {
                    model.selectDate(date)
                } label: {
                    dayLabel(
                        day: day,
                        isSelected: false,
                        isToday: isToday,
                        taskCount: taskCount
                    )
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.background)
                )
            }
        }
        .accessibilityLabel(
            "\(date.formatted(Date.FormatStyle(timeZone: calendar.timeZone).year().month().day()))，\(taskCount) 项任务\(isToday ? "，今天" : "")"
        )
        .accessibilityValue(isSelected ? "已选择" : "未选择")
        .accessibilityIdentifier("calendar-day-\(KshiftDate.isoString(from: date, calendar: calendar))")
    }

    private func dayLabel(
        day: Int,
        isSelected: Bool,
        isToday: Bool,
        taskCount: Int
    ) -> some View {
        VStack(spacing: 4) {
            Text("\(day)")
                .font(.callout.weight(isToday || isSelected ? .bold : .regular))
            if isToday {
                Text("今天")
                    .font(.system(size: 8, weight: .semibold))
            }
            if taskCount > 0 {
                Text("\(taskCount)")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(isSelected ? Color.white.opacity(0.22) : Color.accentColor.opacity(0.14))
                    )
            }
        }
        .frame(maxWidth: .infinity, minHeight: 68)
        .contentShape(Rectangle())
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 38), spacing: 6), count: 7)
    }

    private var monthStart: Date {
        let components = calendar.dateComponents([.year, .month], from: model.selectedDate)
        return calendar.date(from: components) ?? model.selectedDate
    }

    private var monthTitle: String {
        monthStart.formatted(Date.FormatStyle(timeZone: calendar.timeZone).year().month(.wide))
    }

    private var leadingBlankCount: Int {
        let weekday = calendar.component(.weekday, from: monthStart)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private var daysInMonth: Int {
        calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }

    private func shiftMonth(_ amount: Int) {
        let shifted = calendar.date(
            byAdding: .month,
            value: amount,
            to: model.selectedDate
        ) ?? model.selectedDate
        model.selectDate(shifted)
    }

    private func calendarTaskSort(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        if lhs.priority.sortOrder != rhs.priority.sortOrder {
            return lhs.priority.sortOrder < rhs.priority.sortOrder
        }
        return lhs.position < rhs.position
    }
}

private struct CompactCalendarTask: View {
    @ObservedObject var model: AppModel
    let task: TaskItem

    var body: some View {
        Button {
            model.presentDetails(task)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: task.status.symbol)
                    .foregroundStyle(task.status.tint)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .lineLimit(1)
                    Text(task.priority.title + "优先级")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(task.status.title)
                    .font(.caption)
                    .foregroundStyle(task.status.tint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("calendar-task-\(task.id)")
    }
}
