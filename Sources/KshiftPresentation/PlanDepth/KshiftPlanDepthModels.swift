import Foundation

public enum KshiftPlanTaskStatus: String, CaseIterable, Codable, Hashable, Sendable {
    case todo
    case inProgress = "in_progress"
    case blocked
    case done

    public var title: String {
        switch self {
        case .todo: "待处理"
        case .inProgress: "进行中"
        case .blocked: "受阻"
        case .done: "已完成"
        }
    }
}

public enum KshiftPlanPriority: String, CaseIterable, Codable, Hashable, Sendable {
    case low
    case medium
    case high
    case urgent

    public var title: String {
        switch self {
        case .low: "低"
        case .medium: "中"
        case .high: "高"
        case .urgent: "紧急"
        }
    }
}

public enum KshiftPlanRole: String, Codable, Hashable, Sendable {
    case viewer
    case editor
    case admin

    public var canWrite: Bool { self != .viewer }
    public var canRollback: Bool { self == .admin }
}

public struct KshiftPlanPerson: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let initials: String
    public let colorHex: String

    public init(id: UUID, name: String, initials: String, colorHex: String) {
        self.id = id
        self.name = name
        self.initials = initials
        self.colorHex = colorHex
    }
}

public struct KshiftPlanTask: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let projectID: UUID
    public let parentID: UUID?
    public let title: String
    public let descriptionMarkdown: String
    public let status: KshiftPlanTaskStatus
    public let priority: KshiftPlanPriority
    public let assigneeID: UUID?
    public let startsOn: Date
    public let dueOn: Date
    public let estimateMinutes: UInt32
    public let position: Int64
    public let version: UInt64
    public let completedAt: Date?

    public init(
        id: UUID,
        projectID: UUID,
        parentID: UUID? = nil,
        title: String,
        descriptionMarkdown: String,
        status: KshiftPlanTaskStatus,
        priority: KshiftPlanPriority,
        assigneeID: UUID?,
        startsOn: Date,
        dueOn: Date,
        estimateMinutes: UInt32,
        position: Int64,
        version: UInt64,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.parentID = parentID
        self.title = title
        self.descriptionMarkdown = descriptionMarkdown
        self.status = status
        self.priority = priority
        self.assigneeID = assigneeID
        self.startsOn = startsOn
        self.dueOn = dueOn
        self.estimateMinutes = estimateMinutes
        self.position = position
        self.version = version
        self.completedAt = completedAt
    }

    public var isCrossDay: Bool {
        !Calendar(identifier: .gregorian).isDate(startsOn, inSameDayAs: dueOn)
    }
}

public struct KshiftPlanDependency: Codable, Hashable, Sendable {
    public let taskID: UUID
    public let dependsOnTaskID: UUID

    public init(taskID: UUID, dependsOnTaskID: UUID) {
        self.taskID = taskID
        self.dependsOnTaskID = dependsOnTaskID
    }
}

public struct KshiftPlanAttachment: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let sha256: String
    public let mediaType: String
    public let byteSize: UInt64
    public let filename: String

    public init(
        id: UUID,
        sha256: String,
        mediaType: String,
        byteSize: UInt64,
        filename: String
    ) {
        self.id = id
        self.sha256 = sha256
        self.mediaType = mediaType
        self.byteSize = byteSize
        self.filename = filename
    }
}

public struct KshiftPlanAttachmentLink: Codable, Hashable, Sendable {
    public let attachmentID: UUID
    public let taskID: UUID

    public init(attachmentID: UUID, taskID: UUID) {
        self.attachmentID = attachmentID
        self.taskID = taskID
    }
}

public struct KshiftPlanHistoryEntry: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let revision: UInt64
    public let actorID: UUID
    public let action: String
    public let summary: String
    public let occurredAt: Date
    public let restoredFromRevision: UInt64?
    public let contentSHA256: String

    public init(
        id: UUID,
        revision: UInt64,
        actorID: UUID,
        action: String,
        summary: String,
        occurredAt: Date,
        restoredFromRevision: UInt64? = nil,
        contentSHA256: String
    ) {
        self.id = id
        self.revision = revision
        self.actorID = actorID
        self.action = action
        self.summary = summary
        self.occurredAt = occurredAt
        self.restoredFromRevision = restoredFromRevision
        self.contentSHA256 = contentSHA256
    }
}

public struct KshiftPlanDepthSnapshot: Codable, Hashable, Sendable {
    public let projectID: UUID
    public let projectName: String
    public let revision: UInt64
    public let people: [KshiftPlanPerson]
    public let tasks: [KshiftPlanTask]
    public let dependencies: [KshiftPlanDependency]
    public let attachments: [KshiftPlanAttachment]
    public let attachmentLinks: [KshiftPlanAttachmentLink]
    public let history: [KshiftPlanHistoryEntry]

    public init(
        projectID: UUID,
        projectName: String,
        revision: UInt64,
        people: [KshiftPlanPerson],
        tasks: [KshiftPlanTask],
        dependencies: [KshiftPlanDependency],
        attachments: [KshiftPlanAttachment],
        attachmentLinks: [KshiftPlanAttachmentLink],
        history: [KshiftPlanHistoryEntry]
    ) {
        self.projectID = projectID
        self.projectName = projectName
        self.revision = revision
        self.people = people
        self.tasks = tasks
        self.dependencies = dependencies
        self.attachments = attachments
        self.attachmentLinks = attachmentLinks
        self.history = history
    }

    public func attachmentIDs(for taskID: UUID) -> [UUID] {
        attachmentLinks.filter { $0.taskID == taskID }.map(\.attachmentID)
    }
}

public struct KshiftReportRange: Codable, Hashable, Sendable {
    public let startsOn: Date
    public let endsOn: Date

    public init(startsOn: Date, endsOn: Date) {
        self.startsOn = startsOn
        self.endsOn = endsOn
    }
}

public struct KshiftReportTask: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let parentTitle: String?
    public let status: KshiftPlanTaskStatus
    public let priority: KshiftPlanPriority
    public let assigneeName: String?
    public let startsOn: Date
    public let dueOn: Date
    public let estimateMinutes: UInt32
    public let crossDay: Bool
    public let overdue: Bool
    public let dependencyCount: UInt32
    public let subtaskCount: UInt32
    public let attachmentCount: UInt32

    public init(
        id: UUID,
        title: String,
        parentTitle: String?,
        status: KshiftPlanTaskStatus,
        priority: KshiftPlanPriority,
        assigneeName: String?,
        startsOn: Date,
        dueOn: Date,
        estimateMinutes: UInt32,
        crossDay: Bool,
        overdue: Bool,
        dependencyCount: UInt32,
        subtaskCount: UInt32,
        attachmentCount: UInt32
    ) {
        self.id = id
        self.title = title
        self.parentTitle = parentTitle
        self.status = status
        self.priority = priority
        self.assigneeName = assigneeName
        self.startsOn = startsOn
        self.dueOn = dueOn
        self.estimateMinutes = estimateMinutes
        self.crossDay = crossDay
        self.overdue = overdue
        self.dependencyCount = dependencyCount
        self.subtaskCount = subtaskCount
        self.attachmentCount = attachmentCount
    }
}

public struct KshiftReportStatistics: Codable, Hashable, Sendable {
    public let taskCount: UInt32
    public let completedCount: UInt32
    public let overdueCount: UInt32
    public let crossDayCount: UInt32
    public let totalEstimateMinutes: UInt32

    public init(
        taskCount: UInt32,
        completedCount: UInt32,
        overdueCount: UInt32,
        crossDayCount: UInt32,
        totalEstimateMinutes: UInt32
    ) {
        self.taskCount = taskCount
        self.completedCount = completedCount
        self.overdueCount = overdueCount
        self.crossDayCount = crossDayCount
        self.totalEstimateMinutes = totalEstimateMinutes
    }
}

public struct KshiftWorkReport: Codable, Hashable, Sendable {
    public let sourceRevision: UInt64
    public let generatedAt: Date
    public let range: KshiftReportRange
    public let tasks: [KshiftReportTask]
    public let statistics: KshiftReportStatistics
    public let html: String

    public init(
        sourceRevision: UInt64,
        generatedAt: Date,
        range: KshiftReportRange,
        tasks: [KshiftReportTask],
        statistics: KshiftReportStatistics,
        html: String
    ) {
        self.sourceRevision = sourceRevision
        self.generatedAt = generatedAt
        self.range = range
        self.tasks = tasks
        self.statistics = statistics
        self.html = html
    }
}

public enum KshiftPlanDepthCommand: Equatable, Sendable {
    case setTaskStatus(
        taskID: UUID,
        status: KshiftPlanTaskStatus,
        expectedTaskVersion: UInt64,
        expectedRevision: UInt64
    )
    case rollback(targetRevision: UInt64, reason: String, expectedRevision: UInt64)
}

public enum KshiftPlanDepthError: Error, Equatable, Sendable {
    case unavailable
    case unauthorized
    case notFound
    case revisionConflict(currentRevision: UInt64)
    case versionConflict(currentVersion: UInt64)
    case dependencyCycle
    case rollbackUnavailable
    case invalidAttachment
    case invalidResponse
    case released
}

public protocol KshiftPlanDepthBoundary: Sendable {
    func fetchPlanDepth(projectID: UUID) async throws -> KshiftPlanDepthSnapshot
    func execute(_ command: KshiftPlanDepthCommand) async throws -> KshiftPlanDepthSnapshot
    func fetchReport(projectID: UUID, range: KshiftReportRange) async throws -> KshiftWorkReport
}
