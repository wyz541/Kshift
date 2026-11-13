import Foundation

public struct ProjectSummary: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let code: String
    public let colorHex: String
    public let memberIDs: [String]
    public let revision: UInt64

    public init(
        id: String,
        name: String,
        code: String,
        colorHex: String,
        memberIDs: [String],
        revision: UInt64
    ) {
        self.id = id
        self.name = name
        self.code = code
        self.colorHex = colorHex
        self.memberIDs = memberIDs
        self.revision = revision
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case code
        case colorHex = "color_hex"
        case memberIDs = "member_ids"
        case revision
    }
}

public struct Person: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let initials: String
    public let colorHex: String

    public init(id: String, name: String, initials: String, colorHex: String) {
        self.id = id
        self.name = name
        self.initials = initials
        self.colorHex = colorHex
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case initials
        case colorHex = "color_hex"
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
    public let assigneeID: String?
    public let dueDate: String
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
        assigneeID: String?,
        dueDate: String,
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
        self.assigneeID = assigneeID
        self.dueDate = dueDate
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
        case assigneeID = "assignee_id"
        case dueDate = "due_date"
        case position
        case version
        case updatedAt = "updated_at"
        case updatedBy = "updated_by"
        case history
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
    public let assigneeID: String?
    public let dueDate: String
    public let position: Int64?

    public init(
        title: String,
        notes: String,
        status: TaskStatus,
        priority: TaskPriority,
        assigneeID: String?,
        dueDate: String,
        position: Int64? = nil
    ) {
        self.title = title
        self.notes = notes
        self.status = status
        self.priority = priority
        self.assigneeID = assigneeID
        self.dueDate = dueDate
        self.position = position
    }
}

public struct UpdateTaskCommand: Sendable {
    public let taskID: String
    public let expectedTaskVersion: UInt64
    public let title: String
    public let notes: String
    public let status: TaskStatus
    public let priority: TaskPriority
    public let assigneeID: String?
    public let dueDate: String
    public let position: Int64

    public init(
        taskID: String,
        expectedTaskVersion: UInt64,
        title: String,
        notes: String,
        status: TaskStatus,
        priority: TaskPriority,
        assigneeID: String?,
        dueDate: String,
        position: Int64
    ) {
        self.taskID = taskID
        self.expectedTaskVersion = expectedTaskVersion
        self.title = title
        self.notes = notes
        self.status = status
        self.priority = priority
        self.assigneeID = assigneeID
        self.dueDate = dueDate
        self.position = position
    }
}

public struct MoveTaskCommand: Sendable {
    public let taskID: String
    public let expectedTaskVersion: UInt64
    public let assigneeID: String?
    public let dueDate: String
    public let position: Int64

    public init(
        taskID: String,
        expectedTaskVersion: UInt64,
        assigneeID: String?,
        dueDate: String,
        position: Int64
    ) {
        self.taskID = taskID
        self.expectedTaskVersion = expectedTaskVersion
        self.assigneeID = assigneeID
        self.dueDate = dueDate
        self.position = position
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
        case assigneeID = "assignee_id"
        case dueDate = "due_date"
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
            try container.encodeIfPresent(command.assigneeID, forKey: .assigneeID)
            try container.encode(command.dueDate, forKey: .dueDate)
            try container.encodeIfPresent(command.position, forKey: .position)
        case let .update(command):
            try container.encode("update_task", forKey: .kind)
            try container.encode(command.taskID, forKey: .taskID)
            try container.encode(command.expectedTaskVersion, forKey: .expectedTaskVersion)
            try container.encode(command.title, forKey: .title)
            try container.encode(command.notes, forKey: .notes)
            try container.encode(command.status, forKey: .status)
            try container.encode(command.priority, forKey: .priority)
            try container.encodeIfPresent(command.assigneeID, forKey: .assigneeID)
            try container.encode(command.dueDate, forKey: .dueDate)
            try container.encode(command.position, forKey: .position)
        case let .delete(taskID, expectedTaskVersion):
            try container.encode("delete_task", forKey: .kind)
            try container.encode(taskID, forKey: .taskID)
            try container.encode(expectedTaskVersion, forKey: .expectedTaskVersion)
        case let .move(command):
            try container.encode("move_task", forKey: .kind)
            try container.encode(command.taskID, forKey: .taskID)
            try container.encode(command.expectedTaskVersion, forKey: .expectedTaskVersion)
            try container.encodeIfPresent(command.assigneeID, forKey: .assigneeID)
            try container.encode(command.dueDate, forKey: .dueDate)
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

    public static func startOfDay(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }
}
