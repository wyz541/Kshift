import Foundation

public struct ProjectSummary: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let code: String
    public let colorHex: String
    public let timeZone: String
    public let memberIDs: [String]
    public let revision: UInt64

    public init(
        id: String,
        name: String,
        code: String,
        colorHex: String,
        timeZone: String,
        memberIDs: [String],
        revision: UInt64
    ) {
        self.id = id
        self.name = name
        self.code = code
        self.colorHex = colorHex
        self.timeZone = timeZone
        self.memberIDs = memberIDs
        self.revision = revision
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case code
        case colorHex = "color_hex"
        case timeZone = "time_zone"
        case memberIDs = "member_ids"
        case revision
    }
}

public enum ProjectRole: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case viewer
    case editor
    case admin

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .viewer: "只读"
        case .editor: "编辑者"
        case .admin: "管理员"
        }
    }
}

public struct Person: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let initials: String
    public let colorHex: String
    public let role: ProjectRole

    public init(
        id: String,
        name: String,
        initials: String,
        colorHex: String,
        role: ProjectRole = .editor
    ) {
        self.id = id
        self.name = name
        self.initials = initials
        self.colorHex = colorHex
        self.role = role
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case initials
        case colorHex = "color_hex"
        case role
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        initials = try container.decode(String.self, forKey: .initials)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        role = try container.decodeIfPresent(ProjectRole.self, forKey: .role) ?? .editor
    }
}

public enum TaskStatus: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case todo
    case inProgress = "in_progress"
    case blocked
    case done

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .todo: "待处理"
        case .inProgress: "进行中"
        case .blocked: "受阻"
        case .done: "已完成"
        }
    }

    public var symbol: String {
        switch self {
        case .todo: "circle"
        case .inProgress: "circle.lefthalf.filled"
        case .blocked: "exclamationmark.octagon"
        case .done: "checkmark.circle.fill"
        }
    }
}

public enum TaskPriority: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case low
    case medium
    case high
    case urgent

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .low: "低"
        case .medium: "中"
        case .high: "高"
        case .urgent: "紧急"
        }
    }

    public var sortOrder: Int {
        switch self {
        case .urgent: 0
        case .high: 1
        case .medium: 2
        case .low: 3
        }
    }

    public var code: String {
        switch self {
        case .urgent: "P0"
        case .high: "P1"
        case .medium: "P2"
        case .low: "P3"
        }
    }
}

public struct TaskHistoryEntry: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let revision: UInt64
    public let action: String
    public let summary: String
    public let actorID: String
    public let occurredAt: String

    public init(
        id: String,
        revision: UInt64,
        action: String,
        summary: String,
        actorID: String,
        occurredAt: String
    ) {
        self.id = id
        self.revision = revision
        self.action = action
        self.summary = summary
        self.actorID = actorID
        self.occurredAt = occurredAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case revision
        case action
        case summary
        case actorID = "actor_id"
        case occurredAt = "occurred_at"
    }
}

public struct ProjectAuditEntry: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let revision: UInt64
    public let action: String
    public let summary: String
    public let taskID: String?
    public let actorID: String
    public let occurredAt: String

    public init(
        id: String,
        revision: UInt64,
        action: String,
        summary: String,
        taskID: String?,
        actorID: String,
        occurredAt: String
    ) {
        self.id = id
        self.revision = revision
        self.action = action
        self.summary = summary
        self.taskID = taskID
        self.actorID = actorID
        self.occurredAt = occurredAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case revision
        case action
        case summary
        case taskID = "task_id"
        case actorID = "actor_id"
        case occurredAt = "occurred_at"
    }
}

public struct TaskItem: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let projectID: String
    public let title: String
    public let notes: String
    public let status: TaskStatus
    public let priority: TaskPriority
    public let assigneeIDs: [String]
    public let dueDate: String
    public let startsOn: String?
    public let tags: [String]
    public let position: Int64
    public let version: UInt64
    public let updatedAt: String
    public let updatedBy: String
    public let history: [TaskHistoryEntry]

    public init(
        id: String,
        projectID: String,
        title: String,
        notes: String,
        status: TaskStatus,
        priority: TaskPriority,
        assigneeIDs: [String],
        dueDate: String,
        startsOn: String? = nil,
        tags: [String] = [],
        position: Int64,
        version: UInt64,
        updatedAt: String,
        updatedBy: String,
        history: [TaskHistoryEntry]
    ) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.notes = notes
        self.status = status
        self.priority = priority
        self.assigneeIDs = assigneeIDs
        self.dueDate = dueDate
        self.startsOn = startsOn
        self.tags = tags
        self.position = position
        self.version = version
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
        self.history = history
    }

    enum CodingKeys: String, CodingKey {
        case id
        case projectID = "project_id"
        case title
        case notes
        case status
        case priority
        case assigneeIDs = "assignee_ids"
        case dueDate = "due_date"
        case startsOn = "starts_on"
        case tags
        case position
        case version
        case updatedAt = "updated_at"
        case updatedBy = "updated_by"
        case history
    }

    public var descriptionMarkdown: String { notes }

    public var scheduleStartDate: String { startsOn ?? dueDate }

    public var scheduleEndDate: String { dueDate }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        projectID = try container.decode(String.self, forKey: .projectID)
        title = try container.decode(String.self, forKey: .title)
        notes = try container.decode(String.self, forKey: .notes)
        status = try container.decode(TaskStatus.self, forKey: .status)
        priority = try container.decode(TaskPriority.self, forKey: .priority)
        assigneeIDs = try container.decode([String].self, forKey: .assigneeIDs)
        dueDate = try container.decode(String.self, forKey: .dueDate)
        startsOn = try container.decodeIfPresent(String.self, forKey: .startsOn)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        position = try container.decode(Int64.self, forKey: .position)
        version = try container.decode(UInt64.self, forKey: .version)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        updatedBy = try container.decode(String.self, forKey: .updatedBy)
        history = try container.decode([TaskHistoryEntry].self, forKey: .history)
    }
}

public struct ProjectSnapshot: Codable, Hashable, Sendable {
    public let project: ProjectSummary
    public let people: [Person]
    public let tasks: [TaskItem]
    public let audit: [ProjectAuditEntry]

    public init(
        project: ProjectSummary,
        people: [Person],
        tasks: [TaskItem],
        audit: [ProjectAuditEntry]
    ) {
        self.project = project
        self.people = people
        self.tasks = tasks
        self.audit = audit
    }
}

public struct TaskVersionRef: Codable, Hashable, Sendable {
    public let taskID: String
    public let expectedTaskVersion: UInt64

    public init(taskID: String, expectedTaskVersion: UInt64) {
        self.taskID = taskID
        self.expectedTaskVersion = expectedTaskVersion
    }

    enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
        case expectedTaskVersion = "expected_task_version"
    }
}

public struct CreateTaskCommand: Sendable {
    public let title: String
    public let notes: String
    public let status: TaskStatus
    public let priority: TaskPriority
    public let assigneeIDs: [String]
    public let dueDate: String
    public let position: Int64?
    public let startDate: String?
    public let tags: [String]

    public init(
        title: String,
        notes: String,
        status: TaskStatus,
        priority: TaskPriority,
        assigneeIDs: [String],
        dueDate: String,
        position: Int64? = nil,
        startDate: String? = nil,
        tags: [String] = []
    ) {
        self.title = title
        self.notes = notes
        self.status = status
        self.priority = priority
        self.assigneeIDs = assigneeIDs
        self.dueDate = dueDate
        self.position = position
        self.startDate = startDate
        self.tags = tags
    }
}

public struct UpdateTaskCommand: Sendable {
    public let taskID: String
    public let expectedTaskVersion: UInt64
    public let title: String
    public let notes: String
    public let status: TaskStatus
    public let priority: TaskPriority
    public let assigneeIDs: [String]
    public let dueDate: String
    public let position: Int64
    public let startDate: String?
    public let tags: [String]?

    public init(
        taskID: String,
        expectedTaskVersion: UInt64,
        title: String,
        notes: String,
        status: TaskStatus,
        priority: TaskPriority,
        assigneeIDs: [String],
        dueDate: String,
        position: Int64,
        startDate: String? = nil,
        tags: [String]? = nil
    ) {
        self.taskID = taskID
        self.expectedTaskVersion = expectedTaskVersion
        self.title = title
        self.notes = notes
        self.status = status
        self.priority = priority
        self.assigneeIDs = assigneeIDs
        self.dueDate = dueDate
        self.position = position
        self.startDate = startDate
        self.tags = tags
    }
}

public struct MoveTaskCommand: Sendable {
    public let taskID: String
    public let expectedTaskVersion: UInt64
    public let assigneeIDs: [String]
    public let dueDate: String
    public let position: Int64
    public let startDate: String?

    public init(
        taskID: String,
        expectedTaskVersion: UInt64,
        assigneeIDs: [String],
        dueDate: String,
        position: Int64,
        startDate: String? = nil
    ) {
        self.taskID = taskID
        self.expectedTaskVersion = expectedTaskVersion
        self.assigneeIDs = assigneeIDs
        self.dueDate = dueDate
        self.position = position
        self.startDate = startDate
    }
}

public struct SetTasksStatusCommand: Sendable {
    public let items: [TaskVersionRef]
    public let status: TaskStatus

    public init(items: [TaskVersionRef], status: TaskStatus) {
        self.items = items
        self.status = status
    }
}

public enum TaskCommand: Sendable {
    case create(CreateTaskCommand)
    case update(UpdateTaskCommand)
    case delete(taskID: String, expectedTaskVersion: UInt64)
    case move(MoveTaskCommand)
    case setStatus(SetTasksStatusCommand)
}

public struct CommandEnvelope: Encodable, Sendable {
    public let requestID: String
    public let expectedRevision: UInt64
    public let actorID: String
    public let command: TaskCommand

    public init(
        requestID: String = UUID().uuidString,
        expectedRevision: UInt64,
        actorID: String,
        command: TaskCommand
    ) {
        self.requestID = requestID
        self.expectedRevision = expectedRevision
        self.actorID = actorID
        self.command = command
    }

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case expectedRevision = "expected_revision"
        case actorID = "actor_id"
        case command
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requestID, forKey: .requestID)
        try container.encode(expectedRevision, forKey: .expectedRevision)
        try container.encode(actorID, forKey: .actorID)
        try container.encode(command, forKey: .command)
    }
}

extension TaskCommand: Encodable {
    enum CodingKeys: String, CodingKey {
        case kind
        case taskID = "task_id"
        case expectedTaskVersion = "expected_task_version"
        case title
        case notes
        case status
        case priority
        case assigneeIDs = "assignee_ids"
        case dueDate = "due_date"
        case startDate = "start_date"
        case tags
        case position
        case items
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .create(command):
            try container.encode("create_task", forKey: .kind)
            try container.encode(command.title, forKey: .title)
            try container.encode(command.notes, forKey: .notes)
            try container.encode(command.status, forKey: .status)
            try container.encode(command.priority, forKey: .priority)
            try container.encode(command.assigneeIDs, forKey: .assigneeIDs)
            try container.encode(command.dueDate, forKey: .dueDate)
            try container.encodeIfPresent(command.startDate, forKey: .startDate)
            try container.encode(command.tags, forKey: .tags)
            try container.encodeIfPresent(command.position, forKey: .position)
        case let .update(command):
            try container.encode("update_task", forKey: .kind)
            try container.encode(command.taskID, forKey: .taskID)
            try container.encode(command.expectedTaskVersion, forKey: .expectedTaskVersion)
            try container.encode(command.title, forKey: .title)
            try container.encode(command.notes, forKey: .notes)
            try container.encode(command.status, forKey: .status)
            try container.encode(command.priority, forKey: .priority)
            try container.encode(command.assigneeIDs, forKey: .assigneeIDs)
            try container.encode(command.dueDate, forKey: .dueDate)
            try container.encodeIfPresent(command.startDate, forKey: .startDate)
            try container.encodeIfPresent(command.tags, forKey: .tags)
            try container.encode(command.position, forKey: .position)
        case let .delete(taskID, expectedTaskVersion):
            try container.encode("delete_task", forKey: .kind)
            try container.encode(taskID, forKey: .taskID)
            try container.encode(expectedTaskVersion, forKey: .expectedTaskVersion)
        case let .move(command):
            try container.encode("move_task", forKey: .kind)
            try container.encode(command.taskID, forKey: .taskID)
            try container.encode(command.expectedTaskVersion, forKey: .expectedTaskVersion)
            try container.encode(command.assigneeIDs, forKey: .assigneeIDs)
            try container.encode(command.dueDate, forKey: .dueDate)
            try container.encodeIfPresent(command.startDate, forKey: .startDate)
            try container.encode(command.position, forKey: .position)
        case let .setStatus(command):
            try container.encode("set_tasks_status", forKey: .kind)
            try container.encode(command.items, forKey: .items)
            try container.encode(command.status, forKey: .status)
        }
    }
}

public struct CommandError: Codable, Hashable, Sendable {
    public let code: String
    public let message: String
    public let currentRevision: UInt64?
    public let currentTaskVersion: UInt64?
    public let taskID: String?

    public init(
        code: String,
        message: String,
        currentRevision: UInt64?,
        currentTaskVersion: UInt64?,
        taskID: String?
    ) {
        self.code = code
        self.message = message
        self.currentRevision = currentRevision
        self.currentTaskVersion = currentTaskVersion
        self.taskID = taskID
    }

    enum CodingKeys: String, CodingKey {
        case code
        case message
        case currentRevision = "current_revision"
        case currentTaskVersion = "current_task_version"
        case taskID = "task_id"
    }
}

public struct CommandResponse: Codable, Sendable {
    public let ok: Bool
    public let requestID: String
    public let snapshot: ProjectSnapshot?
    public let affectedTaskIDs: [String]
    public let error: CommandError?

    public init(
        ok: Bool,
        requestID: String,
        snapshot: ProjectSnapshot?,
        affectedTaskIDs: [String],
        error: CommandError?
    ) {
        self.ok = ok
        self.requestID = requestID
        self.snapshot = snapshot
        self.affectedTaskIDs = affectedTaskIDs
        self.error = error
    }

    enum CodingKeys: String, CodingKey {
        case ok
        case requestID = "request_id"
        case snapshot
        case affectedTaskIDs = "affected_task_ids"
        case error
    }
}

public struct ProjectsResponse: Codable, Sendable {
    public let ok: Bool
    public let projects: [ProjectSummary]?
    public let error: APIError?
}

public struct SnapshotResponse: Codable, Sendable {
    public let ok: Bool
    public let snapshot: ProjectSnapshot?
    public let error: APIError?
}

public struct APIError: Codable, Hashable, Sendable {
    public let code: String
    public let message: String
}

public enum KshiftDate {
    public static func isoString(from date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 1970,
            components.month ?? 1,
            components.day ?? 1
        )
    }

    public static func date(from string: String, calendar: Calendar = .current) -> Date? {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return calendar.date(from: components)
    }

    public static func addingDays(_ days: Int, to date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    public static func daysBetween(
        from start: Date,
        through end: Date,
        calendar: Calendar = .current
    ) -> Int {
        let normalizedStart = startOfDay(start, calendar: calendar)
        let normalizedEnd = startOfDay(end, calendar: calendar)
        guard normalizedEnd >= normalizedStart else { return 0 }
        let days = calendar.dateComponents([.day], from: normalizedStart, to: normalizedEnd).day ?? 0
        return days + 1
    }

    public static func startOfDay(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }
}

public enum KshiftTime {
    public static func formatTimestamp(
        _ value: String,
        timeZone: TimeZone,
        locale: Locale = .current,
        format: String? = nil
    ) -> String {
        let parser = ISO8601DateFormatter()
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        guard let date = parser.date(from: value) else { return value }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        if let format {
            formatter.dateFormat = format
        } else {
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
        }
        return formatter.string(from: date)
    }
}
