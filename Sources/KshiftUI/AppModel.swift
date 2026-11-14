import KshiftCore
import KshiftPresentation
import Combine
import Foundation

public enum PlannerViewMode: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case peopleSchedule = "people_schedule"
    case board
    case calendar
    case table

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .peopleSchedule: "人员排期"
        case .board: "看板"
        case .calendar: "日历"
        case .table: "表格"
        }
    }

    public var symbol: String {
        switch self {
        case .peopleSchedule: "person.3.sequence.fill"
        case .board: "rectangle.3.group"
        case .calendar: "calendar"
        case .table: "tablecells"
        }
    }
}

public enum SchedulePeriod: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case week
    case month

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .week: "周"
        case .month: "月"
        }
    }
}

public enum ScheduleDensity: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case compact
    case standard
    case comfortable

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .compact: "紧凑"
        case .standard: "标准"
        case .comfortable: "宽松"
        }
    }
}

public enum ScheduleResizeEdge: Sendable {
    case start
    case end
}

public enum TaskSortOption: String, CaseIterable, Identifiable {
    case manual
    case priority
    case title
    case recentlyUpdated

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .manual: "手动顺序"
        case .priority: "优先级"
        case .title: "标题"
        case .recentlyUpdated: "最近更新"
        }
    }
}

public struct TaskFilter: Equatable {
    public var assigneeIDs: Set<String> = []
    public var statuses: Set<TaskStatus> = []
    public var priorities: Set<TaskPriority> = []
    public var tags: Set<String> = []

    public init() {}

    public var isActive: Bool {
        !assigneeIDs.isEmpty || !statuses.isEmpty || !priorities.isEmpty || !tags.isEmpty
    }

    public mutating func reset() {
        assigneeIDs.removeAll()
        statuses.removeAll()
        priorities.removeAll()
        tags.removeAll()
    }
}

public struct TaskDraft: Identifiable {
    public let id = UUID()
    public let projectID: String
    public let taskID: String?
    public let expectedVersion: UInt64
    public var title: String
    public var notes: String
    public var status: TaskStatus
    public var priority: TaskPriority
    public var assigneeIDs: [String]
    public var startDate: Date?
    public var dueDate: Date
    public var tags: [String]
    public var position: Int64

    public init(
        projectID: String,
        taskID: String? = nil,
        expectedVersion: UInt64 = 0,
        title: String = "",
        notes: String = "",
        status: TaskStatus = .todo,
        priority: TaskPriority = .medium,
        assigneeIDs: [String],
        startDate: Date? = nil,
        dueDate: Date,
        tags: [String] = [],
        position: Int64 = 1024
    ) {
        self.projectID = projectID
        self.taskID = taskID
        self.expectedVersion = expectedVersion
        self.title = title
        self.notes = notes
        self.status = status
        self.priority = priority
        self.assigneeIDs = assigneeIDs
        self.startDate = startDate
        self.dueDate = dueDate
        self.tags = tags
        self.position = position
    }

    public var isNew: Bool { taskID == nil }
}

public struct PersonColumn: Identifiable {
    public let id: String
    public let person: Person?
    public let tasks: [TaskItem]

    public var title: String { person?.name ?? "未分配" }
}

public struct ConflictNotice: Identifiable {
    public let id = UUID()
    public let message: String
    public let currentRevision: UInt64?
    public let currentTaskVersion: UInt64?
}

@MainActor
public final class AppModel: ObservableObject {
    @Published public private(set) var projects: [ProjectSummary] = []
    @Published public private(set) var snapshot: ProjectSnapshot?
    @Published public var selectedProjectID: String?
    @Published public var selectedDate = KshiftDate.startOfDay(.now) {
        didSet { persistCurrentPreferences() }
    }
    @Published public var viewMode: PlannerViewMode = .peopleSchedule {
        didSet { persistCurrentPreferences() }
    }
    @Published public var searchText = ""
    @Published public var filter = TaskFilter()
    @Published public var sortOption: TaskSortOption = .manual
    @Published public var schedulePeriod: SchedulePeriod = .week {
        didSet { persistCurrentPreferences() }
    }
    @Published public var scheduleDensity: ScheduleDensity = .compact {
        didSet { persistCurrentPreferences() }
    }
    @Published public var schedulePeopleColumnWidth: CGFloat = 196 {
        didSet { persistCurrentPreferences() }
    }
    @Published public var scheduleDateColumnWidth: CGFloat = 96 {
        didSet { persistCurrentPreferences() }
    }
    @Published public var scheduleScrollAnchorDayID: String? {
        didSet { persistCurrentPreferences() }
    }
    @Published public var collapsedSchedulePersonIDs: Set<String> = [] {
        didSet { persistCurrentPreferences() }
    }
    @Published public var selectedTaskIDs: Set<String> = []
    @Published public var editorDraft: TaskDraft?
    @Published public var detailTaskID: String?
    @Published public var taskPendingDeletion: TaskItem?
    @Published public var conflict: ConflictNotice?
    @Published public var errorMessage: String?
    @Published public private(set) var isLoading = false
    @Published public private(set) var hasLoaded = false

    public let client: any KshiftClientProtocol
    private let platform: any KshiftPlatformCapabilities
    private let userTimeZoneOverride: TimeZone?
    private let fallbackUserTimeZoneToProject: Bool
    private let nowProvider: () -> Date
    private let preferencesStore: PlannerViewPreferencesStore
    private let initialViewMode: PlannerViewMode?
    private var hasBootstrapped = false
    private var isApplyingPreferences = false

    public init(
        client: any KshiftClientProtocol,
        platform: any KshiftPlatformCapabilities,
        userTimeZone: TimeZone? = nil,
        fallbackUserTimeZoneToProject: Bool = false,
        now: @escaping () -> Date = Date.init,
        initialViewMode: PlannerViewMode? = nil,
        preferencesStore: PlannerViewPreferencesStore = PlannerViewPreferencesStore()
    ) {
        self.client = client
        self.platform = platform
        self.userTimeZoneOverride = userTimeZone
        self.fallbackUserTimeZoneToProject = fallbackUserTimeZoneToProject
        self.nowProvider = now
        self.initialViewMode = initialViewMode
        self.preferencesStore = preferencesStore
        self.viewMode = initialViewMode ?? .peopleSchedule
    }

    public var platformCapabilities: any KshiftPlatformCapabilities {
        platform
    }

    public var tasks: [TaskItem] {
        snapshot?.tasks ?? []
    }

    public var people: [Person] {
        snapshot?.people ?? []
    }

    public var selectedProject: ProjectSummary? {
        guard let selectedProjectID else { return snapshot?.project }
        return projects.first(where: { $0.id == selectedProjectID }) ?? snapshot?.project
    }

    public var projectTimeZone: TimeZone {
        TimeZone(identifier: selectedProject?.timeZone ?? "UTC") ?? .gmt
    }

    public var projectCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = projectTimeZone
        return calendar
    }

    public var userTimeZone: TimeZone {
        userTimeZoneOverride
            ?? (fallbackUserTimeZoneToProject ? projectTimeZone : .current)
    }

    public var projectToday: Date {
        KshiftDate.startOfDay(nowProvider(), calendar: projectCalendar)
    }

    public var selectedDateString: String {
        KshiftDate.isoString(from: selectedDate, calendar: projectCalendar)
    }

    public var filteredTasks: [TaskItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = tasks.filter { task in
            if !query.isEmpty {
                let haystack = "\(task.title) \(task.notes) \(task.tags.joined(separator: " "))"
                guard haystack.localizedCaseInsensitiveContains(query) else { return false }
            }
            if !filter.assigneeIDs.isEmpty {
                let matches = task.assigneeIDs.isEmpty
                    ? filter.assigneeIDs.contains("unassigned")
                    : !filter.assigneeIDs.isDisjoint(with: task.assigneeIDs)
                guard matches else { return false }
            }
            if !filter.statuses.isEmpty, !filter.statuses.contains(task.status) {
                return false
            }
            if !filter.priorities.isEmpty, !filter.priorities.contains(task.priority) {
                return false
            }
            if !filter.tags.isEmpty, filter.tags.isDisjoint(with: Set(task.tags)) {
                return false
            }
            return true
        }
        return sorted(filtered)
    }

    public var selectedDateTasks: [TaskItem] {
        filteredTasks.filter { $0.dueDate == selectedDateString }
    }

    public var availableTags: [String] {
        Set(tasks.flatMap(\.tags)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    public var scheduleRangeStart: Date {
        switch schedulePeriod {
        case .week:
            let components = projectCalendar.dateComponents(
                [.yearForWeekOfYear, .weekOfYear],
                from: selectedDate
            )
            return projectCalendar.date(from: components) ?? selectedDate
        case .month:
            let components = projectCalendar.dateComponents([.year, .month], from: selectedDate)
            return projectCalendar.date(from: components) ?? selectedDate
        }
    }

    public var scheduleRangeEnd: Date {
        switch schedulePeriod {
        case .week:
            return KshiftDate.addingDays(6, to: scheduleRangeStart, calendar: projectCalendar)
        case .month:
            let dayCount = projectCalendar.range(
                of: .day,
                in: .month,
                for: scheduleRangeStart
            )?.count ?? 30
            return KshiftDate.addingDays(dayCount - 1, to: scheduleRangeStart, calendar: projectCalendar)
        }
    }

    public var scheduleDays: [Date] {
        let count = KshiftDate.daysBetween(
            from: scheduleRangeStart,
            through: scheduleRangeEnd,
            calendar: projectCalendar
        )
        return (0..<max(count, 1)).compactMap {
            projectCalendar.date(byAdding: .day, value: $0, to: scheduleRangeStart)
        }
    }

    public var scheduleRangeTitle: String {
        switch schedulePeriod {
        case .week:
            let end = scheduleDays.last ?? scheduleRangeEnd
            return "\(formattedScheduleDate(scheduleRangeStart, includeYear: true)) – \(formattedScheduleDate(end))"
        case .month:
            return scheduleRangeStart.formatted(
                Date.FormatStyle(timeZone: projectTimeZone).year().month(.wide)
            )
        }
    }

    public var columns: [PersonColumn] {
        var result = people.map { person in
            PersonColumn(
                id: person.id,
                person: person,
                tasks: selectedDateTasks
                    .filter { $0.assigneeIDs.contains(person.id) }
                    .sorted(by: manualSort)
            )
        }
        let unassigned = selectedDateTasks.filter(\.assigneeIDs.isEmpty).sorted(by: manualSort)
        if !unassigned.isEmpty || filter.assigneeIDs.isEmpty {
            result.append(PersonColumn(id: "unassigned", person: nil, tasks: unassigned))
        }
        return result
    }

    public var completedToday: Int {
        selectedDateTasks.filter { $0.status == .done }.count
    }

    public var blockedToday: Int {
        selectedDateTasks.filter { $0.status == .blocked }.count
    }

    public var selectedTasks: [TaskItem] {
        tasks.filter { selectedTaskIDs.contains($0.id) }
    }

    public var currentActor: Person? {
        people.first(where: { $0.id == client.actorID })
    }

    public func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        await reloadProjects(selectFirst: true)
    }

    public func reloadProjects(selectFirst: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loadedProjects = try await client.projects()
            projects = loadedProjects
            if selectFirst || selectedProjectID == nil {
                selectedProjectID = loadedProjects.first?.id
            }
            if let selectedProjectID {
                snapshot = try await client.snapshot(projectID: selectedProjectID)
                applyPreferences(for: selectedProjectID)
                hasLoaded = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func selectProject(_ projectID: String) async {
        guard projectID != snapshot?.project.id || snapshot == nil else { return }
        persistCurrentPreferences()
        isLoading = true
        defer { isLoading = false }
        do {
            let loadedSnapshot = try await client.snapshot(projectID: projectID)
            selectedProjectID = projectID
            snapshot = loadedSnapshot
            replaceProjectSummary(loadedSnapshot.project)
            applyPreferences(for: projectID)
            selectedTaskIDs.removeAll()
            selectedTasksChanged()
            conflict = nil
            hasLoaded = true
        } catch {
            selectedProjectID = snapshot?.project.id ?? selectedProjectID
            errorMessage = error.localizedDescription
        }
    }

    public func refresh() async {
        guard let projectID = selectedProjectID ?? projects.first?.id else {
            await reloadProjects(selectFirst: true)
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            snapshot = try await client.snapshot(projectID: projectID)
            if let project = snapshot?.project {
                replaceProjectSummary(project)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func presentNewTask(assigneeIDs: [String], date: Date? = nil) {
        guard let projectID = selectedProjectID else { return }
        let position = selectedDateTasks
            .filter { task in
                assigneeIDs.isEmpty
                    ? task.assigneeIDs.isEmpty
                    : !Set(task.assigneeIDs).isDisjoint(with: assigneeIDs)
            }
            .map(\.position)
            .max()
            .map { $0 + 1024 } ?? 1024
        editorDraft = TaskDraft(
            projectID: projectID,
            assigneeIDs: assigneeIDs,
            startDate: KshiftDate.startOfDay(date ?? selectedDate, calendar: projectCalendar),
            dueDate: KshiftDate.startOfDay(date ?? selectedDate, calendar: projectCalendar),
            position: position
        )
    }

    public func selectDate(_ date: Date) {
        selectedDate = KshiftDate.startOfDay(date, calendar: projectCalendar)
        scheduleScrollAnchorDayID = selectedDateString
    }

    public func selectToday() {
        selectedDate = projectToday
        scheduleScrollAnchorDayID = selectedDateString
    }

    public func addDaysToSelection(_ days: Int) {
        selectDate(KshiftDate.addingDays(days, to: selectedDate, calendar: projectCalendar))
    }

    public func setSchedulePeriod(_ period: SchedulePeriod) {
        guard schedulePeriod != period else { return }
        schedulePeriod = period
        scheduleScrollAnchorDayID = KshiftDate.isoString(
            from: scheduleRangeStart,
            calendar: projectCalendar
        )
    }

    public func moveSchedulePeriod(_ amount: Int) {
        let component: Calendar.Component = schedulePeriod == .week ? .weekOfYear : .month
        let nextDate = projectCalendar.date(
            byAdding: component,
            value: amount,
            to: selectedDate
        ) ?? selectedDate
        selectedDate = KshiftDate.startOfDay(nextDate, calendar: projectCalendar)
        scheduleScrollAnchorDayID = KshiftDate.isoString(
            from: scheduleRangeStart,
            calendar: projectCalendar
        )
    }

    public func selectScheduleToday() {
        selectToday()
    }

    public func setScheduleScrollAnchor(_ date: Date) {
        let value = KshiftDate.isoString(from: date, calendar: projectCalendar)
        guard scheduleScrollAnchorDayID != value else { return }
        scheduleScrollAnchorDayID = value
    }

    public func setScheduleDateColumnWidth(_ width: CGFloat) {
        scheduleDateColumnWidth = min(max(width, 96), 360)
    }

    public func setSchedulePeopleColumnWidth(_ width: CGFloat) {
        schedulePeopleColumnWidth = min(max(width, 168), 320)
    }

    public func toggleSchedulePersonCollapsed(_ personID: String) {
        if collapsedSchedulePersonIDs.contains(personID) {
            collapsedSchedulePersonIDs.remove(personID)
        } else {
            collapsedSchedulePersonIDs.insert(personID)
        }
    }

    public func focusSchedule(on task: TaskItem) {
        let start = KshiftDate.date(
            from: task.scheduleStartDate,
            calendar: projectCalendar
        ) ?? selectedDate
        let end = KshiftDate.date(
            from: task.scheduleEndDate,
            calendar: projectCalendar
        ) ?? start
        if end < scheduleRangeStart || start > scheduleRangeEnd {
            selectDate(start)
        } else {
            setScheduleScrollAnchor(start)
        }
    }

    public func isProjectToday(_ date: Date) -> Bool {
        projectCalendar.isDate(date, inSameDayAs: projectToday)
    }

    public func presentEdit(_ task: TaskItem) {
        editorDraft = draft(from: task)
    }

    public func presentDetails(_ task: TaskItem) {
        detailTaskID = task.id
    }

    public func task(withID id: String?) -> TaskItem? {
        guard let id else { return nil }
        return tasks.first(where: { $0.id == id })
    }

    @discardableResult
    public func saveTask(_ draft: TaskDraft) async -> Bool {
        let dueDate = KshiftDate.isoString(from: draft.dueDate, calendar: projectCalendar)
        let startDate = draft.startDate.map {
            KshiftDate.isoString(from: $0, calendar: projectCalendar)
        }
        let command: TaskCommand
        if let taskID = draft.taskID {
            command = .update(
                UpdateTaskCommand(
                    taskID: taskID,
                    expectedTaskVersion: draft.expectedVersion,
                    title: draft.title,
                    notes: draft.notes,
                    status: draft.status,
                    priority: draft.priority,
                    assigneeIDs: draft.assigneeIDs,
                    dueDate: dueDate,
                    position: draft.position,
                    startDate: startDate,
                    tags: draft.tags
                )
            )
        } else {
            command = .create(
                CreateTaskCommand(
                    title: draft.title,
                    notes: draft.notes,
                    status: draft.status,
                    priority: draft.priority,
                    assigneeIDs: draft.assigneeIDs,
                    dueDate: dueDate,
                    position: draft.position,
                    startDate: startDate,
                    tags: draft.tags
                )
            )
        }
        guard let response = await send(command) else { return false }
        return response.ok
    }

    public func requestDelete(_ task: TaskItem) {
        taskPendingDeletion = task
    }

    public func cancelDelete() {
        taskPendingDeletion = nil
    }

    public func deleteTask(_ task: TaskItem) async -> Bool {
        guard let response = await send(
            .delete(taskID: task.id, expectedTaskVersion: task.version)
        ) else { return false }
        if response.ok {
            selectedTaskIDs.remove(task.id)
            detailTaskID = nil
            taskPendingDeletion = nil
        }
        return response.ok
    }

    public func moveTask(
        taskID: String,
        assigneeIDs: [String],
        date: Date = .now,
        position: Int64
    ) async {
        guard let task = task(withID: taskID) else { return }
        let (start, end) = taskDateRange(task)
        let duration = KshiftDate.daysBetween(
            from: start,
            through: end,
            calendar: projectCalendar
        )
        let nextStart = KshiftDate.startOfDay(date, calendar: projectCalendar)
        let nextEnd = KshiftDate.addingDays(max(duration - 1, 0), to: nextStart, calendar: projectCalendar)
        _ = await send(
            .move(
                MoveTaskCommand(
                    taskID: taskID,
                    expectedTaskVersion: task.version,
                    assigneeIDs: assigneeIDs,
                    dueDate: KshiftDate.isoString(from: nextEnd, calendar: projectCalendar),
                    position: position,
                    startDate: KshiftDate.isoString(from: nextStart, calendar: projectCalendar)
                )
            )
        )
    }

    public func moveScheduleTask(
        taskID: String,
        toAssigneeID assigneeID: String?,
        date: Date
    ) async {
        guard let task = task(withID: taskID) else { return }
        await moveTask(
            taskID: taskID,
            assigneeIDs: assigneeID.map { [$0] } ?? [],
            date: date,
            position: task.position
        )
    }

    public func resizeScheduleTask(
        taskID: String,
        edge: ScheduleResizeEdge,
        date: Date
    ) async {
        guard let task = task(withID: taskID) else { return }
        let (currentStart, currentEnd) = taskDateRange(task)
        let requestedDate = KshiftDate.startOfDay(date, calendar: projectCalendar)
        let nextStart: Date
        let nextEnd: Date
        switch edge {
        case .start:
            nextStart = min(requestedDate, currentEnd)
            nextEnd = currentEnd
        case .end:
            nextStart = currentStart
            nextEnd = max(requestedDate, currentStart)
        }
        _ = await send(
            .move(
                MoveTaskCommand(
                    taskID: taskID,
                    expectedTaskVersion: task.version,
                    assigneeIDs: task.assigneeIDs,
                    dueDate: KshiftDate.isoString(from: nextEnd, calendar: projectCalendar),
                    position: task.position,
                    startDate: KshiftDate.isoString(from: nextStart, calendar: projectCalendar)
                )
            )
        )
    }

    public func setStatus(_ task: TaskItem, to status: TaskStatus) async {
        guard task.status != status else { return }
        _ = await send(.setStatus(SetTasksStatusCommand(
            items: [TaskVersionRef(taskID: task.id, expectedTaskVersion: task.version)],
            status: status
        )))
    }

    public func toggleDone(_ task: TaskItem) async {
        let nextStatus: TaskStatus = task.status == .done ? .todo : .done
        _ = await send(.setStatus(SetTasksStatusCommand(
            items: [TaskVersionRef(taskID: task.id, expectedTaskVersion: task.version)],
            status: nextStatus
        )))
    }

    public func setStatusForSelection(_ status: TaskStatus) async {
        let items = selectedTasks.map {
            TaskVersionRef(taskID: $0.id, expectedTaskVersion: $0.version)
        }
        guard !items.isEmpty else { return }
        if let response = await send(
            .setStatus(SetTasksStatusCommand(items: items, status: status))
        ), response.ok {
            selectedTaskIDs.removeAll()
            selectedTasksChanged()
        }
    }

    public func toggleSelection(_ taskID: String) {
        if selectedTaskIDs.contains(taskID) {
            selectedTaskIDs.remove(taskID)
        } else {
            selectedTaskIDs.insert(taskID)
        }
        selectedTasksChanged()
    }

    public func clearSelection() {
        selectedTaskIDs.removeAll()
        selectedTasksChanged()
    }

    public func taskCount(on date: Date) -> Int {
        let key = KshiftDate.isoString(from: date, calendar: projectCalendar)
        return filteredTasks.filter { $0.dueDate == key }.count
    }

    public func actorName(for actorID: String) -> String {
        people.first(where: { $0.id == actorID })?.name ?? actorID
    }

    public func dismissConflict() {
        conflict = nil
    }

    public func resolveConflictByRefreshing() async {
        conflict = nil
        await refresh()
    }

    public func clearError() {
        errorMessage = nil
    }

    public func openAccessibilitySettings() async {
        let urlString =
            platform.platform == .macOS
            ? "x-apple.systempreferences:com.apple.Accessibility-Settings.extension"
            : "app-settings:"
        guard let url = URL(string: urlString) else { return }
        _ = await platform.openExternalURL(url)
    }

    private func send(_ command: TaskCommand) async -> CommandResponse? {
        guard let projectID = selectedProjectID, let revision = snapshot?.project.revision else {
            errorMessage = "项目尚未加载。"
            return nil
        }
        do {
            let response = try await client.execute(
                projectID: projectID,
                envelope: CommandEnvelope(
                    expectedRevision: revision,
                    actorID: client.actorID,
                    command: command
                )
            )
            if response.ok, let nextSnapshot = response.snapshot {
                snapshot = nextSnapshot
                replaceProjectSummary(nextSnapshot.project)
                conflict = nil
                platform.perform(.success)
                await refresh()
            } else if let error = response.error {
                if error.code == "version_conflict" || error.code == "revision_conflict" {
                    conflict = ConflictNotice(
                        message: error.message,
                        currentRevision: error.currentRevision,
                        currentTaskVersion: error.currentTaskVersion
                    )
                } else {
                    errorMessage = error.message
                }
            }
            return response
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func draft(from task: TaskItem) -> TaskDraft {
        TaskDraft(
            projectID: task.projectID,
            taskID: task.id,
            expectedVersion: task.version,
            title: task.title,
            notes: task.notes,
            status: task.status,
            priority: task.priority,
            assigneeIDs: task.assigneeIDs,
            startDate: KshiftDate.date(from: task.scheduleStartDate, calendar: projectCalendar),
            dueDate: KshiftDate.date(from: task.dueDate, calendar: projectCalendar) ?? selectedDate,
            tags: task.tags,
            position: task.position
        )
    }

    private func replaceProjectSummary(_ summary: ProjectSummary) {
        if let index = projects.firstIndex(where: { $0.id == summary.id }) {
            projects[index] = summary
        }
    }

    public func assigneeNames(for task: TaskItem) -> String {
        guard !task.assigneeIDs.isEmpty else { return "未分配" }
        return task.assigneeIDs.map(actorName).joined(separator: "、")
    }

    public func displayTimestamp(_ value: String) -> String {
        KshiftTime.formatTimestamp(value, timeZone: userTimeZone)
    }

    private func taskDateRange(_ task: TaskItem) -> (Date, Date) {
        let start = KshiftDate.date(
            from: task.scheduleStartDate,
            calendar: projectCalendar
        ) ?? selectedDate
        let end = KshiftDate.date(
            from: task.scheduleEndDate,
            calendar: projectCalendar
        ) ?? start
        return (min(start, end), max(start, end))
    }

    private func formattedScheduleDate(_ date: Date, includeYear: Bool = false) -> String {
        var style = Date.FormatStyle(timeZone: projectTimeZone).month(.abbreviated).day()
        if includeYear {
            style = style.year()
        }
        return date.formatted(style)
    }

    private func applyPreferences(for projectID: String) {
        isApplyingPreferences = true
        defer { isApplyingPreferences = false }

        let saved = preferencesStore.load(projectID: projectID)
        let preferences = saved ?? PlannerViewPreferences(
            viewMode: initialViewMode ?? .peopleSchedule,
            selectedDate: KshiftDate.isoString(from: projectToday, calendar: projectCalendar),
            schedulePeriod: .week,
            scheduleDensity: .compact,
            schedulePeopleColumnWidth: 196,
            scheduleDateColumnWidth: 96,
            scheduleScrollAnchorDayID: KshiftDate.isoString(
                from: projectToday,
                calendar: projectCalendar
            )
        )

        viewMode = initialViewMode ?? preferences.viewMode
        selectedDate = KshiftDate.date(
            from: preferences.selectedDate ?? "",
            calendar: projectCalendar
        ) ?? projectToday
        schedulePeriod = preferences.schedulePeriod
        scheduleDensity = preferences.scheduleDensity
        schedulePeopleColumnWidth = min(max(preferences.schedulePeopleColumnWidth, 168), 320)
        scheduleDateColumnWidth = min(max(preferences.scheduleDateColumnWidth, 96), 360)
        scheduleScrollAnchorDayID = preferences.scheduleScrollAnchorDayID
            ?? KshiftDate.isoString(from: selectedDate, calendar: projectCalendar)
        collapsedSchedulePersonIDs = preferences.collapsedSchedulePersonIDs
    }

    private func persistCurrentPreferences() {
        guard !isApplyingPreferences, let projectID = snapshot?.project.id else { return }
        preferencesStore.save(
            PlannerViewPreferences(
                viewMode: viewMode,
                selectedDate: KshiftDate.isoString(from: selectedDate, calendar: projectCalendar),
                schedulePeriod: schedulePeriod,
                scheduleDensity: scheduleDensity,
                schedulePeopleColumnWidth: schedulePeopleColumnWidth,
                scheduleDateColumnWidth: scheduleDateColumnWidth,
                scheduleScrollAnchorDayID: scheduleScrollAnchorDayID,
                collapsedSchedulePersonIDs: collapsedSchedulePersonIDs
            ),
            projectID: projectID
        )
    }

    private func sorted(_ tasks: [TaskItem]) -> [TaskItem] {
        switch sortOption {
        case .manual:
            tasks.sorted(by: manualSort)
        case .priority:
            tasks.sorted {
                if $0.priority.sortOrder == $1.priority.sortOrder {
                    return manualSort($0, $1)
                }
                return $0.priority.sortOrder < $1.priority.sortOrder
            }
        case .title:
            tasks.sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        case .recentlyUpdated:
            tasks.sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    private func manualSort(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        if lhs.position == rhs.position {
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        return lhs.position < rhs.position
    }

    private func selectedTasksChanged() {
        if selectedTaskIDs.isEmpty {
            selectedTaskIDs.removeAll()
        }
    }
}
