import KshiftCore
import KshiftPresentation
import Combine
import Foundation

public enum PlannerViewMode: String, CaseIterable, Identifiable {
    case board
    case calendar
    case table

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .board: "看板"
        case .calendar: "日历"
        case .table: "表格"
        }
    }

    public var symbol: String {
        switch self {
        case .board: "rectangle.3.group"
        case .calendar: "calendar"
        case .table: "tablecells"
        }
    }
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

    public init() {}

    public var isActive: Bool {
        !assigneeIDs.isEmpty || !statuses.isEmpty || !priorities.isEmpty
    }

    public mutating func reset() {
        assigneeIDs.removeAll()
        statuses.removeAll()
        priorities.removeAll()
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
    public var dueDate: Date
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
        dueDate: Date,
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
        self.dueDate = dueDate
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
    @Published public var selectedDate = KshiftDate.startOfDay(.now)
    @Published public var viewMode: PlannerViewMode = .board
    @Published public var searchText = ""
    @Published public var filter = TaskFilter()
    @Published public var sortOption: TaskSortOption = .manual
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
    private var hasBootstrapped = false

    public init(client: any KshiftClientProtocol, platform: any KshiftPlatformCapabilities) {
        self.client = client
        self.platform = platform
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

    public var userTimeZone: TimeZone { .current }

    public var selectedDateString: String {
        KshiftDate.isoString(from: selectedDate, calendar: projectCalendar)
    }

    public var filteredTasks: [TaskItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = tasks.filter { task in
            if !query.isEmpty {
                let haystack = "\(task.title) \(task.notes)"
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
            return true
        }
        return sorted(filtered)
    }

    public var selectedDateTasks: [TaskItem] {
        filteredTasks.filter { $0.dueDate == selectedDateString }
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
                if !hasLoaded {
                    alignSelectedDateToProject()
                }
                hasLoaded = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func selectProject(_ projectID: String) async {
        guard projectID != selectedProjectID || snapshot == nil else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            selectedProjectID = projectID
            snapshot = try await client.snapshot(projectID: projectID)
            alignSelectedDateToProject()
            selectedTaskIDs.removeAll()
            selectedTasksChanged()
            conflict = nil
            hasLoaded = true
        } catch {
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
            dueDate: KshiftDate.startOfDay(date ?? selectedDate, calendar: projectCalendar),
            position: position
        )
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
                    position: draft.position
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
                    position: draft.position
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
        _ = await send(
            .move(
                MoveTaskCommand(
                    taskID: taskID,
                    expectedTaskVersion: task.version,
                    assigneeIDs: assigneeIDs,
                    dueDate: KshiftDate.isoString(from: date, calendar: projectCalendar),
                    position: position
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
        let key = KshiftDate.isoString(from: date)
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
            dueDate: KshiftDate.date(from: task.dueDate, calendar: projectCalendar) ?? selectedDate,
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

    private func alignSelectedDateToProject() {
        selectedDate = KshiftDate.startOfDay(.now, calendar: projectCalendar)
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
