import Foundation
import KshiftCore

public struct PeopleScheduleTaskSlice: Identifiable, Hashable, Sendable {
    public let task: TaskItem
    public let lane: Int
    public let startIndex: Int
    public let endIndex: Int

    public var id: String { "\(task.id)-\(lane)" }
    public var dayCount: Int { endIndex - startIndex + 1 }

    public init(
        task: TaskItem,
        lane: Int,
        startIndex: Int,
        endIndex: Int
    ) {
        self.task = task
        self.lane = lane
        self.startIndex = startIndex
        self.endIndex = endIndex
    }
}

public enum PeopleScheduleLayout {
    public static func slices(
        for tasks: [TaskItem],
        days: [Date],
        calendar: Calendar
    ) -> [PeopleScheduleTaskSlice] {
        guard let rangeStart = days.first, let rangeEnd = days.last else { return [] }
        let normalizedStart = calendar.startOfDay(for: rangeStart)
        let normalizedEnd = calendar.startOfDay(for: rangeEnd)

        let candidates = tasks.compactMap { task -> Candidate? in
            guard let taskStart = KshiftDate.date(from: task.scheduleStartDate, calendar: calendar),
                  let taskEnd = KshiftDate.date(from: task.scheduleEndDate, calendar: calendar)
            else { return nil }
            let boundedStart = min(calendar.startOfDay(for: taskStart), calendar.startOfDay(for: taskEnd))
            let boundedEnd = max(calendar.startOfDay(for: taskStart), calendar.startOfDay(for: taskEnd))
            guard boundedEnd >= normalizedStart, boundedStart <= normalizedEnd else { return nil }

            let visibleStart = max(boundedStart, normalizedStart)
            let visibleEnd = min(boundedEnd, normalizedEnd)
            let startIndex = calendar.dateComponents(
                [.day],
                from: normalizedStart,
                to: visibleStart
            ).day ?? 0
            let endIndex = calendar.dateComponents(
                [.day],
                from: normalizedStart,
                to: visibleEnd
            ).day ?? startIndex
            return Candidate(task: task, startIndex: startIndex, endIndex: endIndex)
        }
        .sorted(by: candidateSort)

        var laneEnds: [Int] = []
        return candidates.map { candidate in
            let lane: Int
            if let reusable = laneEnds.firstIndex(where: { $0 < candidate.startIndex }) {
                lane = reusable
                laneEnds[reusable] = candidate.endIndex
            } else {
                lane = laneEnds.count
                laneEnds.append(candidate.endIndex)
            }
            return PeopleScheduleTaskSlice(
                task: candidate.task,
                lane: lane,
                startIndex: candidate.startIndex,
                endIndex: candidate.endIndex
            )
        }
    }

    public static func laneCount(for slices: [PeopleScheduleTaskSlice]) -> Int {
        (slices.map(\.lane).max() ?? -1) + 1
    }

    public static func hiddenSuccessorMarkers(
        in slices: [PeopleScheduleTaskSlice],
        visibleStartIndex: Int,
        visibleEndIndex: Int
    ) -> [Int: PeopleScheduleTaskSlice] {
        let byLane = Dictionary(grouping: slices, by: \.lane)
        var markers: [Int: PeopleScheduleTaskSlice] = [:]
        for (lane, laneSlices) in byLane {
            let hasVisibleTask = laneSlices.contains {
                $0.startIndex <= visibleEndIndex && $0.endIndex >= visibleStartIndex
            }
            guard !hasVisibleTask else { continue }
            if let successor = laneSlices
                .filter({ $0.startIndex > visibleEndIndex })
                .min(by: { $0.startIndex < $1.startIndex })
            {
                markers[lane] = successor
            }
        }
        return markers
    }

    public static func stickyTitleLeading(
        taskStartIndex: Int,
        dateColumnWidth: CGFloat,
        taskWidth: CGFloat,
        horizontalOffset: CGFloat,
        viewportWidth: CGFloat,
        inset: CGFloat = 8
    ) -> CGFloat {
        let taskX = CGFloat(taskStartIndex) * dateColumnWidth
        let visibleLeft = max(taskX, horizontalOffset)
        let visibleRight = min(taskX + taskWidth, horizontalOffset + viewportWidth)
        guard visibleRight > visibleLeft else { return inset }
        return max(inset, visibleLeft - taskX + inset)
    }

    public static func statusSortWeight(_ status: TaskStatus) -> Int {
        switch status {
        case .blocked: 0
        case .inProgress: 1
        case .todo: 2
        case .done: 3
        }
    }

    private struct Candidate {
        let task: TaskItem
        let startIndex: Int
        let endIndex: Int
    }

    private static func candidateSort(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.startIndex != rhs.startIndex {
            return lhs.startIndex < rhs.startIndex
        }
        if lhs.task.priority.sortOrder != rhs.task.priority.sortOrder {
            return lhs.task.priority.sortOrder < rhs.task.priority.sortOrder
        }
        let leftStatus = statusSortWeight(lhs.task.status)
        let rightStatus = statusSortWeight(rhs.task.status)
        if leftStatus != rightStatus {
            return leftStatus < rightStatus
        }
        if lhs.task.position != rhs.task.position {
            return lhs.task.position < rhs.task.position
        }
        return lhs.task.title.localizedStandardCompare(rhs.task.title) == .orderedAscending
    }
}
