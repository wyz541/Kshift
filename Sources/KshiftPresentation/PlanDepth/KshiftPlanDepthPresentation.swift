import Foundation

public enum KshiftPlanDepthViewMode: String, CaseIterable, Identifiable, Sendable {
    case board
    case gantt
    case history
    case report

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .board: "看板"
        case .gantt: "甘特"
        case .history: "历史"
        case .report: "报告"
        }
    }
}

public struct KshiftPlanDepthFilter: Equatable, Sendable {
    public var searchText: String
    public var assigneeID: UUID?
    public var status: KshiftPlanTaskStatus?

    public init(searchText: String = "", assigneeID: UUID? = nil, status: KshiftPlanTaskStatus? = nil) {
        self.searchText = searchText
        self.assigneeID = assigneeID
        self.status = status
    }
}

public struct KshiftPlanTaskPresentation: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let markdown: String
    public let status: KshiftPlanTaskStatus
    public let priority: KshiftPlanPriority
    public let assigneeName: String
    public let scheduleLabel: String
    public let dependencyCount: Int
    public let subtaskCount: Int
    public let attachmentCount: Int
    public let isCrossDay: Bool
    public let isCompleted: Bool
    public let accessibilityLabel: String
    public let accessibilityHint: String
}

public struct KshiftPlanBoardColumn: Identifiable, Hashable, Sendable {
    public let status: KshiftPlanTaskStatus
    public let title: String
    public let tasks: [KshiftPlanTaskPresentation]

    public var id: KshiftPlanTaskStatus { status }
}

public struct KshiftGanttRow: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let status: KshiftPlanTaskStatus
    public let assigneeName: String
    public let startFraction: Double
    public let widthFraction: Double
    public let crossDay: Bool
    public let dependencyCount: Int
    public let dateLabel: String
    public let accessibilityLabel: String
}

public struct KshiftGanttPresentation: Hashable, Sendable {
    public let startDateLabel: String
    public let endDateLabel: String
    public let dayCount: Int
    public let rows: [KshiftGanttRow]
}

public struct KshiftHistoryRow: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let revision: UInt64
    public let revisionLabel: String
    public let actorName: String
    public let actionLabel: String
    public let summary: String
    public let timeLabel: String
    public let restoredFromLabel: String?
    public let canRollback: Bool
    public let accessibilityLabel: String
}

public struct KshiftAttachmentPresentation: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let filename: String
    public let mediaType: String
    public let sizeLabel: String
    public let sha256Short: String
    public let accessibilityLabel: String
}

public struct KshiftReportRowPresentation: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let status: KshiftPlanTaskStatus
    public let assignee: String
    public let schedule: String
    public let estimate: String
    public let risk: String
    public let accessibilityLabel: String
}

public struct KshiftReportPresentation: Hashable, Sendable {
    public let sourceRevision: UInt64
    public let sourceRevisionLabel: String
    public let rangeLabel: String
    public let summaryLabel: String
    public let rows: [KshiftReportRowPresentation]
    public let html: String
}

public struct KshiftPlanDepthPresentation: Hashable, Sendable {
    public let projectTitle: String
    public let revisionLabel: String
    public let progressLabel: String
    public let progressFraction: Double
    public let columns: [KshiftPlanBoardColumn]
    public let gantt: KshiftGanttPresentation
    public let history: [KshiftHistoryRow]
    public let attachments: [KshiftAttachmentPresentation]
    public let hiddenTaskCount: Int
    public let accessibilitySummary: String
}

public struct KshiftPlanDepthPresentationMapper: Sendable {
    public static let maximumVisibleInteractiveCards = 6

    private let locale: Locale
    private let timeZone: TimeZone
    private let calendar: Calendar

    public init(locale: Locale = .current, timeZone: TimeZone = .current) {
        self.locale = locale
        self.timeZone = timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    public func makePresentation(
        snapshot: KshiftPlanDepthSnapshot,
        filter: KshiftPlanDepthFilter,
        viewerRole: KshiftPlanRole
    ) -> KshiftPlanDepthPresentation {
        let people = Dictionary(uniqueKeysWithValues: snapshot.people.map { ($0.id, $0.name) })
        let dependencies = Dictionary(grouping: snapshot.dependencies, by: \.taskID)
        let subtasks = Dictionary(grouping: snapshot.tasks.compactMap { task in
            task.parentID.map { ($0, task) }
        }, by: \.0)

        let matching = snapshot.tasks
            .filter { matches($0, filter: filter) }
            .sorted(by: taskSort)
        let visible = Array(matching.prefix(Self.maximumVisibleInteractiveCards))
        let hiddenCount = max(0, matching.count - visible.count)

        let taskPresentations = Dictionary(uniqueKeysWithValues: visible.map { task in
            let assignee = task.assigneeID.flatMap { people[$0] } ?? "未分配"
            let dependencyCount = dependencies[task.id]?.count ?? 0
            let subtaskCount = subtasks[task.id]?.count ?? 0
            let attachmentCount = snapshot.attachmentIDs(for: task.id).count
            let schedule = "\(dateLabel(task.startsOn)) 至 \(dateLabel(task.dueOn))"
            let nextAction = task.status == .done ? "重新打开" : "标记完成"
            return (
                task.id,
                KshiftPlanTaskPresentation(
                    id: task.id,
                    title: task.title,
                    markdown: task.descriptionMarkdown,
                    status: task.status,
                    priority: task.priority,
                    assigneeName: assignee,
                    scheduleLabel: schedule,
                    dependencyCount: dependencyCount,
                    subtaskCount: subtaskCount,
                    attachmentCount: attachmentCount,
                    isCrossDay: task.isCrossDay,
                    isCompleted: task.status == .done,
                    accessibilityLabel: "\(task.title)，\(task.status.title)，优先级\(task.priority.title)，负责人\(assignee)，\(schedule)",
                    accessibilityHint: "\(nextAction)。任务版本 \(task.version)，项目版本 \(snapshot.revision)。"
                )
            )
        })

        let columns = [
            KshiftPlanTaskStatus.todo,
            .inProgress,
            .blocked,
            .done,
        ].map { status in
            KshiftPlanBoardColumn(
                status: status,
                title: status.title,
                tasks: visible.compactMap { task in
                    task.status == status ? taskPresentations[task.id] : nil
                }
            )
        }

        let gantt = makeGantt(snapshot: snapshot, tasks: matching, people: people)
        let history = snapshot.history.map { entry in
            let actor = people[entry.actorID] ?? "未知成员"
            return KshiftHistoryRow(
                id: entry.id,
                revision: entry.revision,
                revisionLabel: "r\(entry.revision)",
                actorName: actor,
                actionLabel: actionLabel(entry.action),
                summary: entry.summary,
                timeLabel: historyTimeLabel(entry.occurredAt),
                restoredFromLabel: entry.restoredFromRevision.map { "恢复自 r\($0)" },
                canRollback: viewerRole.canRollback,
                accessibilityLabel: "版本 \(entry.revision)，\(actor)\(actionLabel(entry.action))，\(entry.summary)"
            )
        }
        let attachments = snapshot.attachments.map { attachment in
            KshiftAttachmentPresentation(
                id: attachment.id,
                filename: attachment.filename,
                mediaType: attachment.mediaType,
                sizeLabel: ByteCountFormatter.string(
                    fromByteCount: Int64(attachment.byteSize),
                    countStyle: .file
                ),
                sha256Short: String(attachment.sha256.prefix(12)),
                accessibilityLabel: "附件 \(attachment.filename)，\(attachment.mediaType)，\(ByteCountFormatter.string(fromByteCount: Int64(attachment.byteSize), countStyle: .file))"
            )
        }

        let completed = snapshot.tasks.filter { $0.status == .done }.count
        return KshiftPlanDepthPresentation(
            projectTitle: snapshot.projectName,
            revisionLabel: "r\(snapshot.revision)",
            progressLabel: "\(completed) / \(snapshot.tasks.count) 已完成",
            progressFraction: snapshot.tasks.isEmpty ? 0 : Double(completed) / Double(snapshot.tasks.count),
            columns: columns,
            gantt: gantt,
            history: history,
            attachments: attachments,
            hiddenTaskCount: hiddenCount,
            accessibilitySummary: "\(snapshot.projectName)，共 \(snapshot.tasks.count) 项任务，\(completed) 项已完成。当前筛选显示 \(matching.count) 项。"
        )
    }

    public func makeReportPresentation(_ report: KshiftWorkReport) -> KshiftReportPresentation {
        KshiftReportPresentation(
            sourceRevision: report.sourceRevision,
            sourceRevisionLabel: "来源 r\(report.sourceRevision)",
            rangeLabel: "\(dateLabel(report.range.startsOn)) 至 \(dateLabel(report.range.endsOn))",
            summaryLabel: "任务 \(report.statistics.taskCount) 项，完成 \(report.statistics.completedCount) 项，逾期 \(report.statistics.overdueCount) 项，跨日 \(report.statistics.crossDayCount) 项。",
            rows: report.tasks.map { task in
                let schedule = "\(dateLabel(task.startsOn)) 至 \(dateLabel(task.dueOn))"
                let risk = task.overdue ? "逾期" : task.crossDay ? "跨日" : "正常"
                return KshiftReportRowPresentation(
                    id: task.id,
                    title: task.title,
                    status: task.status,
                    assignee: task.assigneeName ?? "未分配",
                    schedule: schedule,
                    estimate: "\(task.estimateMinutes) 分钟",
                    risk: risk,
                    accessibilityLabel: "\(task.title)，\(task.status.title)，负责人\(task.assigneeName ?? "未分配")，\(schedule)，\(risk)"
                )
            },
            html: report.html
        )
    }

    private func makeGantt(
        snapshot: KshiftPlanDepthSnapshot,
        tasks: [KshiftPlanTask],
        people: [UUID: String]
    ) -> KshiftGanttPresentation {
        guard let earliest = snapshot.tasks.map(\.startsOn).min(),
              let latest = snapshot.tasks.map(\.dueOn).max()
        else {
            return KshiftGanttPresentation(
                startDateLabel: "无任务",
                endDateLabel: "无任务",
                dayCount: 0,
                rows: []
            )
        }
        let windowStart = calendar.startOfDay(for: earliest)
        let windowEnd = calendar.startOfDay(for: latest)
        let dayCount = max(1, (calendar.dateComponents([.day], from: windowStart, to: windowEnd).day ?? 0) + 1)
        let dependencyCounts = Dictionary(grouping: snapshot.dependencies, by: \.taskID).mapValues(\.count)
        let rows = tasks.map { task in
            let offset = calendar.dateComponents(
                [.day],
                from: windowStart,
                to: calendar.startOfDay(for: task.startsOn)
            ).day ?? 0
            let span = max(1, (calendar.dateComponents([.day], from: task.startsOn, to: task.dueOn).day ?? 0) + 1)
            let startFraction = min(1, max(0, Double(offset) / Double(dayCount)))
            let widthFraction = min(1 - startFraction, max(1 / Double(dayCount), Double(span) / Double(dayCount)))
            let assignee = task.assigneeID.flatMap { people[$0] } ?? "未分配"
            let dateRange = "\(dateLabel(task.startsOn)) 至 \(dateLabel(task.dueOn))"
            return KshiftGanttRow(
                id: task.id,
                title: task.title,
                status: task.status,
                assigneeName: assignee,
                startFraction: startFraction,
                widthFraction: widthFraction,
                crossDay: task.isCrossDay,
                dependencyCount: dependencyCounts[task.id] ?? 0,
                dateLabel: dateRange,
                accessibilityLabel: "\(task.title)，\(dateRange)，负责人\(assignee)，\(task.isCrossDay ? "跨日任务" : "单日任务")"
            )
        }.sorted {
            if $0.startFraction != $1.startFraction { return $0.startFraction < $1.startFraction }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
        return KshiftGanttPresentation(
            startDateLabel: dateLabel(windowStart),
            endDateLabel: dateLabel(windowEnd),
            dayCount: dayCount,
            rows: rows
        )
    }

    private func matches(_ task: KshiftPlanTask, filter: KshiftPlanDepthFilter) -> Bool {
        if let assigneeID = filter.assigneeID, task.assigneeID != assigneeID {
            return false
        }
        if let status = filter.status, task.status != status {
            return false
        }
        let search = filter.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !search.isEmpty else { return true }
        return task.title.localizedCaseInsensitiveContains(search)
            || task.descriptionMarkdown.localizedCaseInsensitiveContains(search)
    }

    private func taskSort(_ left: KshiftPlanTask, _ right: KshiftPlanTask) -> Bool {
        let leftStatus = statusOrder(left.status)
        let rightStatus = statusOrder(right.status)
        if leftStatus != rightStatus { return leftStatus < rightStatus }
        let leftPriority = priorityOrder(left.priority)
        let rightPriority = priorityOrder(right.priority)
        if leftPriority != rightPriority { return leftPriority < rightPriority }
        if left.position != right.position { return left.position < right.position }
        return left.title.localizedStandardCompare(right.title) == .orderedAscending
    }

    private func statusOrder(_ status: KshiftPlanTaskStatus) -> Int {
        switch status {
        case .inProgress: 0
        case .blocked: 1
        case .todo: 2
        case .done: 3
        }
    }

    private func priorityOrder(_ priority: KshiftPlanPriority) -> Int {
        switch priority {
        case .urgent: 0
        case .high: 1
        case .medium: 2
        case .low: 3
        }
    }

    private func actionLabel(_ action: String) -> String {
        switch action {
        case "created": "创建任务"
        case "updated": "更新任务"
        case "deleted": "删除任务"
        case "parent_changed": "调整子任务"
        case "dependencies_replaced": "调整依赖"
        case "attachment_added": "添加附件"
        case "rollback": "回退版本"
        case "seeded": "载入快照"
        default: action
        }
    }

    private func dateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.calendar = calendar
        formatter.dateFormat = "MM-dd"
        return formatter.string(from: date)
    }

    private func historyTimeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.calendar = calendar
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
