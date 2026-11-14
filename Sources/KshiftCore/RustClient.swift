import Foundation
import KshiftFFI
import KshiftPresentation

/// Production client adapter for the bounded C ABI in `kshift-ffi`.
///
/// The shared UI only sees `KshiftClientProtocol`. This type keeps the
/// protobuf and transport details below the Swift package boundary and maps
/// the FFI JSON projection into the presentation models used by the planner.
public final class RustClient: KshiftClientProtocol, KshiftPlanDepthBoundary, @unchecked Sendable {
    public let actorID: String

    private let clientID: String
    private let client: KshiftClient?
    private let setupError: String?
    private let deadlineMilliseconds: UInt64

    public init(
        actorID: String = "person-mia",
        clientID: String = UUID().uuidString,
        endpoint: String? = nil,
        caPEM: Data? = nil,
        token: String? = nil,
        deadlineMilliseconds: UInt64 = 10_000
    ) {
        self.actorID = actorID
        self.clientID = clientID
        self.deadlineMilliseconds = deadlineMilliseconds

        let environment = ProcessInfo.processInfo.environment
        let resolvedEndpoint = endpoint ?? environment["KSHIFT_ENDPOINT"]
        let resolvedToken = token ?? environment["KSHIFT_TOKEN"]
        let resolvedCA = caPEM ?? Self.caPEM(from: environment)

        guard let resolvedEndpoint, !resolvedEndpoint.isEmpty else {
            self.client = nil
            self.setupError = "缺少 KSHIFT_ENDPOINT。"
            return
        }
        guard let resolvedCA else {
            self.client = nil
            self.setupError = "缺少 KSHIFT_CA_PATH 或 KSHIFT_CA_PEM。"
            return
        }

        do {
            let client = try KshiftClient(
                endpoint: resolvedEndpoint,
                caPEM: resolvedCA,
                tlsDomain: environment["KSHIFT_TLS_DOMAIN"],
                defaultDeadlineMilliseconds: deadlineMilliseconds
            )
            if let resolvedToken, !resolvedToken.isEmpty {
                try client.updateToken(resolvedToken)
            }
            self.client = client
            self.setupError = nil
        } catch {
            self.client = nil
            self.setupError = error.localizedDescription
        }
    }

    public func projects() async throws -> [ProjectSummary] {
        let client = try requireClient()
        return try await Task.detached {
            let data = try client.listProjects(deadlineMilliseconds: self.deadlineMilliseconds)
            let values = try JSONDecoder().decode([OfficialProjectSummary].self, from: data)
            return values.map(Self.mapProjectSummary)
        }.value
    }

    public func snapshot(projectID: String) async throws -> ProjectSnapshot {
        let client = try requireClient()
        return try await Task.detached {
            let data = try client.snapshot(
                projectID: projectID,
                deadlineMilliseconds: self.deadlineMilliseconds
            )
            return try Self.decodeSnapshot(data)
        }.value
    }

    public func execute(
        projectID: String,
        envelope: CommandEnvelope
    ) async throws -> CommandResponse {
        switch envelope.command {
        case let .setStatus(command):
            return try await executeBatchStatus(
                projectID: projectID,
                envelope: envelope,
                command: command
            )
        case .create, .update, .delete, .move:
            return try await executeSingle(projectID: projectID, envelope: envelope)
        }
    }

    private func executeSingle(
        projectID: String,
        envelope: CommandEnvelope
    ) async throws -> CommandResponse {
        let client = try requireClient()
        let request: Data
        do {
            request = try Self.encodeCommand(projectID: projectID, envelope: envelope, clientID: clientID)
        } catch {
            throw KshiftClientError.invalidResponse(error.localizedDescription)
        }

        do {
            let snapshot = try await Task.detached { [client, deadlineMilliseconds] in
                _ = try client.executeCommand(
                    request,
                    deadlineMilliseconds: deadlineMilliseconds
                )
                let data = try client.snapshot(
                    projectID: projectID,
                    deadlineMilliseconds: deadlineMilliseconds
                )
                let value = try JSONDecoder().decode(OfficialProjectSnapshot.self, from: data)
                return Self.mapSnapshot(value)
            }.value
            return CommandResponse(
                ok: true,
                requestID: envelope.requestID,
                snapshot: snapshot,
                affectedTaskIDs: Self.affectedTaskIDs(for: envelope.command),
                error: nil
            )
        } catch let error as KshiftCFFIError {
            return Self.failure(error, requestID: envelope.requestID)
        } catch {
            throw KshiftClientError.transport(error.localizedDescription)
        }
    }

    private func executeBatchStatus(
        projectID: String,
        envelope: CommandEnvelope,
        command: SetTasksStatusCommand
    ) async throws -> CommandResponse {
        let client = try requireClient()
        let request: Data
        do {
            request = try Self.encodeBatchStatusCommand(
                projectID: projectID,
                requestID: envelope.requestID,
                clientID: clientID,
                expectedRevision: envelope.expectedRevision,
                items: command.items,
                status: command.status
            )
        } catch {
            throw KshiftClientError.invalidResponse(error.localizedDescription)
        }

        do {
            let snapshot = try await Task.detached { [client, deadlineMilliseconds] in
                _ = try client.executeCommand(
                    request,
                    deadlineMilliseconds: deadlineMilliseconds
                )
                let data = try client.snapshot(
                    projectID: projectID,
                    deadlineMilliseconds: deadlineMilliseconds
                )
                let value = try JSONDecoder().decode(OfficialProjectSnapshot.self, from: data)
                return Self.mapSnapshot(value)
            }.value
            return CommandResponse(
                ok: true,
                requestID: envelope.requestID,
                snapshot: snapshot,
                affectedTaskIDs: command.items.map(\.taskID),
                error: nil
            )
        } catch let error as KshiftCFFIError {
            return Self.failure(error, requestID: envelope.requestID)
        } catch {
            throw KshiftClientError.transport(error.localizedDescription)
        }
    }

    private func requireClient() throws -> KshiftClient {
        guard let client else {
            throw KshiftClientError.ffiUnavailable(setupError ?? "Rust FFI 客户端尚未配置。")
        }
        return client
    }

    private static func caPEM(from environment: [String: String]) -> Data? {
        if let pem = environment["KSHIFT_CA_PEM"], !pem.isEmpty {
            return Data(pem.utf8)
        }
        guard let path = environment["KSHIFT_CA_PATH"], !path.isEmpty else {
            return nil
        }
        return try? Data(contentsOf: URL(fileURLWithPath: path))
    }

    private static func failure(
        _ error: KshiftCFFIError,
        requestID: String
    ) -> CommandResponse {
        let code: String
        if error.entityID != nil, error.entityVersion != nil {
            code = "version_conflict"
        } else if error.currentRevision != nil {
            code = "revision_conflict"
        } else {
            code = error.code
        }
        return CommandResponse(
            ok: false,
            requestID: requestID,
            snapshot: nil,
            affectedTaskIDs: [],
            error: CommandError(
                code: code,
                message: error.message,
                currentRevision: error.currentRevision,
                currentTaskVersion: error.entityVersion,
                taskID: error.entityID
            )
        )
    }

    private static func affectedTaskIDs(for command: TaskCommand) -> [String] {
        switch command {
        case .create:
            []
        case let .update(value):
            [value.taskID]
        case let .delete(taskID, _):
            [taskID]
        case let .move(value):
            [value.taskID]
        case let .setStatus(value):
            value.items.map(\.taskID)
        }
    }

    private static func encodeCommand(
        projectID: String,
        envelope: CommandEnvelope,
        clientID: String
    ) throws -> Data {
        let command: FFICommand
        switch envelope.command {
        case let .create(value):
            command = .createTask(
                FFICreateTask(
                    title: value.title,
                    descriptionMarkdown: value.notes,
                    status: value.status.rawValue,
                    priority: value.priority.rawValue,
                    assigneeIDs: value.assigneeIDs,
                    plannedOn: value.dueDate,
                    dueOn: value.dueDate,
                    tags: [],
                    dependencyTaskIDs: []
                )
            )
        case let .update(value):
            command = .updateTask(
                FFIUpdateTask(
                    taskID: value.taskID,
                    expectedEntityVersion: value.expectedTaskVersion,
                    title: value.title,
                    descriptionMarkdown: value.notes,
                    status: value.status.rawValue,
                    priority: value.priority.rawValue,
                    assigneeIDs: value.assigneeIDs,
                    plannedOn: value.dueDate,
                    dueOn: value.dueDate,
                    tags: nil,
                    dependencyTaskIDs: nil
                )
            )
        case let .delete(taskID, expectedTaskVersion):
            command = .deleteTask(
                FFIDeleteTask(
                    taskID: taskID,
                    expectedEntityVersion: expectedTaskVersion
                )
            )
        case let .move(value):
            command = .updateTask(
                FFIUpdateTask(
                    taskID: value.taskID,
                    expectedEntityVersion: value.expectedTaskVersion,
                    assigneeIDs: value.assigneeIDs,
                    plannedOn: value.dueDate,
                    dueOn: value.dueDate
                )
            )
        case let .setStatus(value):
            guard let item = value.items.first else {
                throw KshiftClientError.invalidResponse("批量状态命令没有任务。")
            }
            command = .updateTask(
                FFIUpdateTask(
                    taskID: item.taskID,
                    expectedEntityVersion: item.expectedTaskVersion,
                    status: value.status.rawValue
                )
            )
        }

        let commandID = UUID(uuidString: envelope.requestID) ?? UUID()
        let body = FFICommandEnvelope(
            clientID: clientID,
            commandID: commandID.uuidString,
            projectID: projectID,
            expectedProjectRevision: envelope.expectedRevision,
            command: command
        )
        let encoder = JSONEncoder()
        return try encoder.encode(body)
    }

    private static func encodeBatchStatusCommand(
        projectID: String,
        requestID: String,
        clientID: String,
        expectedRevision: UInt64,
        items: [TaskVersionRef],
        status: TaskStatus
    ) throws -> Data {
        let mutations = items.map { item in
            FFITaskMutation.updateTask(
                FFIUpdateTask(
                    taskID: item.taskID,
                    expectedEntityVersion: item.expectedTaskVersion,
                    status: status.rawValue
                )
            )
        }
        let body = FFICommandEnvelope(
            clientID: clientID,
            commandID: UUID(uuidString: requestID)?.uuidString ?? UUID().uuidString,
            projectID: projectID,
            expectedProjectRevision: expectedRevision,
            command: .batchUpdateTasks(mutations)
        )
        return try JSONEncoder().encode(body)
    }

    private static func mapProjectSummary(_ value: OfficialProjectSummary) -> ProjectSummary {
        ProjectSummary(
            id: value.id,
            name: value.name,
            code: projectCode(from: value.name),
            colorHex: projectColor(from: value.id),
            timeZone: value.timeZone ?? "UTC",
            memberIDs: [],
            revision: value.currentRevision
        )
    }

    static func decodeSnapshot(_ data: Data) throws -> ProjectSnapshot {
        let value = try JSONDecoder().decode(OfficialProjectSnapshot.self, from: data)
        return mapSnapshot(value)
    }

    private static func mapSnapshot(_ value: OfficialProjectSnapshot) -> ProjectSnapshot {
        let members = value.members.map { member in
            Person(
                id: member.userID,
                name: member.displayName,
                initials: initials(from: member.displayName),
                colorHex: projectColor(from: member.userID)
            )
        }
        let project = ProjectSummary(
            id: value.project.id,
            name: value.project.name,
            code: projectCode(from: value.project.name),
            colorHex: projectColor(from: value.project.id),
            timeZone: value.project.timeZone ?? "UTC",
            memberIDs: members.map(\.id),
            revision: value.project.currentRevision
        )
        let audit = (value.audit ?? []).map { entry in
            ProjectAuditEntry(
                id: entry.id,
                revision: entry.revision ?? 0,
                action: entry.action,
                summary: entry.summary,
                taskID: entry.taskID,
                actorID: entry.actorID,
                occurredAt: entry.occurredAt
            )
        }
        let historyByTask = Dictionary(grouping: audit.filter { $0.taskID != nil }) { entry in
            entry.taskID ?? ""
        }
        let tasks = value.tasks.enumerated().map { index, task in
            TaskItem(
                id: task.id,
                projectID: task.projectID,
                title: task.title,
                notes: task.descriptionMarkdown,
                status: mapStatus(task.status),
                priority: mapPriority(task.priority),
                assigneeIDs: task.assigneeIDs,
                dueDate: task.dueOn ?? task.plannedOn,
                position: Int64(index) * 1_024,
                version: task.version,
                updatedAt: task.updatedAt,
                updatedBy: task.updatedBy,
                history: (historyByTask[task.id] ?? []).map { entry in
                    TaskHistoryEntry(
                        id: entry.id,
                        revision: entry.revision,
                        action: entry.action,
                        summary: entry.summary,
                        actorID: entry.actorID,
                        occurredAt: entry.occurredAt
                    )
                }
            )
        }
        return ProjectSnapshot(project: project, people: members, tasks: tasks, audit: audit)
    }

    private static func mapStatus(_ value: String) -> TaskStatus {
        switch value {
        case "in_progress":
            .inProgress
        case "blocked":
            .blocked
        case "done":
            .done
        default:
            .todo
        }
    }

    private static func mapPriority(_ value: String) -> TaskPriority {
        switch value {
        case "urgent":
            .urgent
        case "high":
            .high
        case "medium":
            .medium
        case "low", "none":
            .low
        default:
            .medium
        }
    }

    private static func projectCode(from name: String) -> String {
        let code = name.uppercased().prefix(12)
        return String(code)
    }

    private static func projectColor(from id: String) -> String {
        let palette = ["#0A84FF", "#30D158", "#FF9F0A", "#FF375F", "#BF5AF2", "#64D2FF"]
        let index = id.utf8.reduce(0) { ($0 + Int($1)) % palette.count }
        return palette[index]
    }

    private static func initials(from name: String) -> String {
        let words = name.split(whereSeparator: \.isWhitespace)
        if words.count > 1 {
            return words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        }
        let characters = Array(name)
        return String(characters.prefix(2)).uppercased()
    }
}

private struct OfficialProjectSummary: Decodable {
    let id: String
    let name: String
    let timeZone: String?
    let currentRevision: UInt64

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case timeZone = "time_zone"
        case currentRevision = "current_revision"
    }
}

private struct OfficialProjectSnapshot: Decodable {
    let project: OfficialProject
    let members: [OfficialProjectMember]
    let tasks: [OfficialTask]
    let audit: [OfficialProjectAuditEntry]?
}

private struct OfficialProjectAuditEntry: Decodable {
    let id: String
    let revision: UInt64?
    let action: String
    let summary: String
    let taskID: String?
    let actorID: String
    let occurredAt: String

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

private struct OfficialProject: Decodable {
    let id: String
    let name: String
    let timeZone: String?
    let currentRevision: UInt64

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case timeZone = "time_zone"
        case currentRevision = "current_revision"
    }
}

private struct OfficialProjectMember: Decodable {
    let userID: String
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
    }
}

private struct OfficialTask: Decodable {
    let id: String
    let projectID: String
    let title: String
    let descriptionMarkdown: String
    let status: String
    let priority: String
    let assigneeIDs: [String]
    let plannedOn: String
    let dueOn: String?
    let version: UInt64
    let updatedBy: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case projectID = "project_id"
        case title
        case descriptionMarkdown = "description_markdown"
        case status
        case priority
        case assigneeIDs = "assignee_ids"
        case plannedOn = "planned_on"
        case dueOn = "due_on"
        case version
        case updatedBy = "updated_by"
        case updatedAt = "updated_at"
    }
}

private struct FFICommandEnvelope: Encodable {
    let clientID: String
    let commandID: String
    let projectID: String
    let expectedProjectRevision: UInt64
    let command: FFICommand

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case commandID = "command_id"
        case projectID = "project_id"
        case expectedProjectRevision = "expected_project_revision"
        case command
    }
}

private enum FFICommand: Encodable {
    case createTask(FFICreateTask)
    case updateTask(FFIUpdateTask)
    case deleteTask(FFIDeleteTask)
    case batchUpdateTasks([FFITaskMutation])

    enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .createTask(value):
            try container.encode("create_task", forKey: .type)
            try container.encode(value, forKey: .value)
        case let .updateTask(value):
            try container.encode("update_task", forKey: .type)
            try container.encode(value, forKey: .value)
        case let .deleteTask(value):
            try container.encode("delete_task", forKey: .type)
            try container.encode(value, forKey: .value)
        case let .batchUpdateTasks(mutations):
            try container.encode("batch_update_tasks", forKey: .type)
            try container.encode(FFIBatchUpdateTasks(mutations: mutations), forKey: .value)
        }
    }
}

private struct FFIBatchUpdateTasks: Encodable {
    let mutations: [FFITaskMutation]
}

private enum FFITaskMutation: Encodable {
    case updateTask(FFIUpdateTask)

    enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .updateTask(value):
            try container.encode("update_task", forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}

private struct FFICreateTask: Encodable {
    let title: String
    let descriptionMarkdown: String
    let status: String
    let priority: String
    let assigneeIDs: [String]
    let plannedOn: String
    let dueOn: String?
    let tags: [String]
    let dependencyTaskIDs: [String]

    enum CodingKeys: String, CodingKey {
        case title
        case descriptionMarkdown = "description_markdown"
        case status
        case priority
        case assigneeIDs = "assignee_ids"
        case plannedOn = "planned_on"
        case dueOn = "due_on"
        case tags
        case dependencyTaskIDs = "dependency_task_ids"
    }
}

private struct FFIUpdateTask: Encodable {
    let taskID: String
    let expectedEntityVersion: UInt64
    let title: String?
    let descriptionMarkdown: String?
    let status: String?
    let priority: String?
    let assigneeIDs: [String]?
    let plannedOn: String?
    let dueOn: String?
    let tags: [String]?
    let dependencyTaskIDs: [String]?

    init(
        taskID: String,
        expectedEntityVersion: UInt64,
        title: String? = nil,
        descriptionMarkdown: String? = nil,
        status: String? = nil,
        priority: String? = nil,
        assigneeIDs: [String]? = nil,
        plannedOn: String? = nil,
        dueOn: String? = nil,
        tags: [String]? = nil,
        dependencyTaskIDs: [String]? = nil
    ) {
        self.taskID = taskID
        self.expectedEntityVersion = expectedEntityVersion
        self.title = title
        self.descriptionMarkdown = descriptionMarkdown
        self.status = status
        self.priority = priority
        self.assigneeIDs = assigneeIDs
        self.plannedOn = plannedOn
        self.dueOn = dueOn
        self.tags = tags
        self.dependencyTaskIDs = dependencyTaskIDs
    }

    enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
        case expectedEntityVersion = "expected_entity_version"
        case title
        case descriptionMarkdown = "description_markdown"
        case status
        case priority
        case assigneeIDs = "assignee_ids"
        case plannedOn = "planned_on"
        case dueOn = "due_on"
        case tags
        case dependencyTaskIDs = "dependency_task_ids"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(taskID, forKey: .taskID)
        try container.encode(expectedEntityVersion, forKey: .expectedEntityVersion)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(descriptionMarkdown, forKey: .descriptionMarkdown)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(priority, forKey: .priority)
        try container.encodeIfPresent(assigneeIDs, forKey: .assigneeIDs)
        try container.encodeIfPresent(plannedOn, forKey: .plannedOn)
        try container.encodeIfPresent(dueOn, forKey: .dueOn)
        try container.encodeIfPresent(tags, forKey: .tags)
        try container.encodeIfPresent(dependencyTaskIDs, forKey: .dependencyTaskIDs)
    }
}

private struct FFIDeleteTask: Encodable {
    let taskID: String
    let expectedEntityVersion: UInt64

    enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
        case expectedEntityVersion = "expected_entity_version"
    }
}

extension RustClient {
    public func fetchPlanDepth(projectID: UUID) async throws -> KshiftPlanDepthSession {
        do {
            let client = try requireClient()
            let deadline = deadlineMilliseconds
            return try await Task.detached {
                let data = try client.planDepthSnapshot(
                    projectID: projectID.uuidString,
                    deadlineMilliseconds: deadline
                )
                return try Self.decodePlanDepthSession(data)
            }.value
        } catch let error as KshiftCFFIError {
            throw Self.planDepthError(error)
        } catch let error as KshiftPlanDepthError {
            throw error
        } catch {
            throw KshiftPlanDepthError.unavailable
        }
    }

    public func execute(
        projectID: UUID,
        _ command: KshiftPlanDepthCommand
    ) async throws -> KshiftPlanDepthSnapshot {
        let request = Self.planDepthCommandRequest(projectID: projectID, command: command)
        let commandData: Data
        do {
            commandData = try JSONEncoder().encode(request)
        } catch {
            throw KshiftPlanDepthError.invalidResponse
        }
        do {
            let client = try requireClient()
            let deadline = deadlineMilliseconds
            return try await Task.detached {
                let data = try client.executePlanDepthCommand(
                    commandData,
                    deadlineMilliseconds: deadline
                )
                return try Self.decodePlanDepthSession(data).snapshot
            }.value
        } catch let error as KshiftCFFIError {
            throw Self.planDepthError(error)
        } catch let error as KshiftPlanDepthError {
            throw error
        } catch {
            throw KshiftPlanDepthError.unavailable
        }
    }

    public func fetchReport(
        projectID: UUID,
        range: KshiftReportRange
    ) async throws -> KshiftWorkReport {
        do {
            let client = try requireClient()
            let deadline = deadlineMilliseconds
            return try await Task.detached {
                let data = try client.planDepthReport(
                    projectID: projectID.uuidString,
                    startsOn: Self.planDepthDateString(range.startsOn),
                    endsOn: Self.planDepthDateString(range.endsOn),
                    today: Self.planDepthDateString(.now),
                    deadlineMilliseconds: deadline
                )
                return try Self.decodePlanReport(data)
            }.value
        } catch let error as KshiftCFFIError {
            throw Self.planDepthError(error)
        } catch let error as KshiftPlanDepthError {
            throw error
        } catch {
            throw KshiftPlanDepthError.unavailable
        }
    }

    private static func planDepthCommandRequest(
        projectID: UUID,
        command: KshiftPlanDepthCommand
    ) -> FFIPlanDepthCommandRequest {
        switch command {
        case let .setTaskStatus(taskID, status, expectedTaskVersion, expectedRevision):
            return FFIPlanDepthCommandRequest(
                requestID: UUID().uuidString,
                projectID: projectID.uuidString,
                expectedRevision: expectedRevision,
                command: .setTaskStatus(
                    taskID: taskID.uuidString,
                    status: status.rawValue,
                    expectedVersion: expectedTaskVersion
                )
            )
        case let .rollback(targetRevision, reason, expectedRevision):
            return FFIPlanDepthCommandRequest(
                requestID: UUID().uuidString,
                projectID: projectID.uuidString,
                expectedRevision: expectedRevision,
                command: .rollback(targetRevision: targetRevision, reason: reason)
            )
        }
    }

    private static func decodePlanDepthSession(_ data: Data) throws -> KshiftPlanDepthSession {
        let dto = try JSONDecoder().decode(RustPlanDepthSessionDTO.self, from: data)
        let snapshot = try mapPlanDepthSnapshot(dto.snapshot)
        guard let role = KshiftPlanRole(rawValue: dto.actorRole) else {
            throw KshiftPlanDepthError.invalidResponse
        }
        return KshiftPlanDepthSession(snapshot: snapshot, viewerRole: role)
    }

    private static func mapPlanDepthSnapshot(
        _ dto: RustPlanDepthSnapshotDTO
    ) throws -> KshiftPlanDepthSnapshot {
        guard let projectID = UUID(uuidString: dto.project.id) else {
            throw KshiftPlanDepthError.invalidResponse
        }
        let people = try dto.people.map { person -> KshiftPlanPerson in
            guard let id = UUID(uuidString: person.id) else {
                throw KshiftPlanDepthError.invalidResponse
            }
            return KshiftPlanPerson(
                id: id,
                name: person.name,
                initials: person.initials,
                colorHex: person.colorHex
            )
        }
        let tasks = try dto.tasks.map { task -> KshiftPlanTask in
            guard let id = UUID(uuidString: task.id),
                  let taskProjectID = UUID(uuidString: task.projectID),
                  let status = KshiftPlanTaskStatus(rawValue: task.status),
                  let priority = planDepthPriority(task.priority),
                  let startsOn = planDepthDate(task.startsOn),
                  let dueOn = planDepthDate(task.dueOn)
            else {
                throw KshiftPlanDepthError.invalidResponse
            }
            let parentID = task.parentID.flatMap(UUID.init(uuidString:))
            let assigneeID = task.assigneeID.flatMap(UUID.init(uuidString:))
            let completedAt = task.completedAt.flatMap(planDepthTimestamp)
            return KshiftPlanTask(
                id: id,
                projectID: taskProjectID,
                parentID: parentID,
                title: task.title,
                descriptionMarkdown: task.descriptionMarkdown,
                status: status,
                priority: priority,
                assigneeID: assigneeID,
                startsOn: startsOn,
                dueOn: dueOn,
                estimateMinutes: task.estimateMinutes,
                position: task.position,
                version: task.version,
                completedAt: completedAt
            )
        }
        let dependencies = try dto.dependencies.map { dependency -> KshiftPlanDependency in
            guard let taskID = UUID(uuidString: dependency.taskID),
                  let dependsOnTaskID = UUID(uuidString: dependency.dependsOnTaskID)
            else {
                throw KshiftPlanDepthError.invalidResponse
            }
            return KshiftPlanDependency(taskID: taskID, dependsOnTaskID: dependsOnTaskID)
        }
        let attachments = try dto.attachments.map { attachment -> KshiftPlanAttachment in
            guard let id = UUID(uuidString: attachment.id) else {
                throw KshiftPlanDepthError.invalidResponse
            }
            return KshiftPlanAttachment(
                id: id,
                sha256: attachment.sha256,
                mediaType: attachment.mediaType,
                byteSize: attachment.byteSize,
                filename: attachment.filename
            )
        }
        let attachmentLinks = try dto.attachmentLinks.map { link -> KshiftPlanAttachmentLink in
            guard let attachmentID = UUID(uuidString: link.attachmentID),
                  let taskID = UUID(uuidString: link.taskID)
            else {
                throw KshiftPlanDepthError.invalidResponse
            }
            return KshiftPlanAttachmentLink(attachmentID: attachmentID, taskID: taskID)
        }
        let history = try dto.history.map { entry -> KshiftPlanHistoryEntry in
            guard let id = UUID(uuidString: entry.id),
                  let actorID = UUID(uuidString: entry.actorID),
                  let occurredAt = planDepthTimestamp(entry.occurredAt)
            else {
                throw KshiftPlanDepthError.invalidResponse
            }
            return KshiftPlanHistoryEntry(
                id: id,
                revision: entry.revision,
                actorID: actorID,
                action: entry.action,
                summary: entry.summary,
                occurredAt: occurredAt,
                restoredFromRevision: entry.restoredFromRevision,
                contentSHA256: entry.contentSHA256
            )
        }
        return KshiftPlanDepthSnapshot(
            projectID: projectID,
            projectName: dto.project.name,
            revision: dto.project.revision,
            people: people,
            tasks: tasks,
            dependencies: dependencies,
            attachments: attachments,
            attachmentLinks: attachmentLinks,
            history: history
        )
    }

    private static func decodePlanReport(_ data: Data) throws -> KshiftWorkReport {
        let dto = try JSONDecoder().decode(RustPlanReportDTO.self, from: data)
        guard let startsOn = planDepthDate(dto.range.startsOn),
              let endsOn = planDepthDate(dto.range.endsOn),
              let generatedAt = planDepthTimestamp(dto.generatedAt)
        else {
            throw KshiftPlanDepthError.invalidResponse
        }
        let tasks = try dto.tasks.map { task -> KshiftReportTask in
            guard let id = UUID(uuidString: task.id),
                  let status = KshiftPlanTaskStatus(rawValue: task.status),
                  let priority = planDepthPriority(task.priority),
                  let taskStartsOn = planDepthDate(task.startsOn),
                  let taskDueOn = planDepthDate(task.dueOn)
            else {
                throw KshiftPlanDepthError.invalidResponse
            }
            return KshiftReportTask(
                id: id,
                title: task.title,
                parentTitle: task.parentTitle,
                status: status,
                priority: priority,
                assigneeName: task.assigneeName,
                startsOn: taskStartsOn,
                dueOn: taskDueOn,
                estimateMinutes: task.estimateMinutes,
                crossDay: task.crossDay,
                overdue: task.overdue,
                dependencyCount: task.dependencyCount,
                subtaskCount: task.subtaskCount,
                attachmentCount: task.attachmentCount
            )
        }
        return KshiftWorkReport(
            sourceRevision: dto.sourceRevision,
            generatedAt: generatedAt,
            range: KshiftReportRange(startsOn: startsOn, endsOn: endsOn),
            tasks: tasks,
            statistics: KshiftReportStatistics(
                taskCount: dto.statistics.taskCount,
                completedCount: dto.statistics.completedCount,
                overdueCount: dto.statistics.overdueCount,
                crossDayCount: dto.statistics.crossDayCount,
                totalEstimateMinutes: dto.statistics.totalEstimateMinutes
            ),
            html: dto.html
        )
    }

    private static func planDepthError(_ error: KshiftCFFIError) -> KshiftPlanDepthError {
        if error.entityVersion != nil {
            return .versionConflict(currentVersion: error.entityVersion ?? 0)
        }
        if error.currentRevision != nil {
            return .revisionConflict(currentRevision: error.currentRevision ?? 0)
        }
        if error.status == KshiftFFIStatus.permissionDenied
            || error.status == KshiftFFIStatus.unauthenticated
        {
            return .unauthorized
        }
        if error.status == KshiftFFIStatus.notFound {
            return .notFound
        }
        if error.status == KshiftFFIStatus.conflict {
            return .revisionConflict(currentRevision: 0)
        }
        if error.status == KshiftFFIStatus.invalidState {
            if error.message.contains("依赖") || error.message.contains("循环") {
                return .dependencyCycle
            }
            if error.message.contains("回退") {
                return .rollbackUnavailable
            }
            if error.message.contains("附件") {
                return .invalidAttachment
            }
        }
        if error.status == KshiftFFIStatus.invalidArgument,
           error.message.contains("附件")
        {
            return .invalidAttachment
        }
        if error.status == KshiftFFIStatus.protocolError {
            return .invalidResponse
        }
        return .unavailable
    }

    private static func planDepthPriority(_ value: String) -> KshiftPlanPriority? {
        switch value {
        case "none", "low": .low
        case "medium": .medium
        case "high": .high
        case "urgent": .urgent
        default: nil
        }
    }

    private static func planDepthDate(_ value: String) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func planDepthDateString(_ value: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month, .day], from: value)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 1970,
            components.month ?? 1,
            components.day ?? 1
        )
    }

    private static func planDepthTimestamp(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

private struct FFIPlanDepthCommandRequest: Encodable {
    let requestID: String
    let projectID: String
    let expectedRevision: UInt64
    let command: FFIPlanDepthCommand

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case projectID = "project_id"
        case expectedRevision = "expected_revision"
        case command
    }
}

private enum FFIPlanDepthCommand: Encodable {
    case setTaskStatus(taskID: String, status: String, expectedVersion: UInt64)
    case rollback(targetRevision: UInt64, reason: String)

    enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    private struct SetTaskStatus: Encodable {
        let taskID: String
        let status: String
        let expectedVersion: UInt64

        enum CodingKeys: String, CodingKey {
            case taskID = "task_id"
            case status
            case expectedVersion = "expected_version"
        }
    }

    private struct Rollback: Encodable {
        let targetRevision: UInt64
        let reason: String

        enum CodingKeys: String, CodingKey {
            case targetRevision = "target_revision"
            case reason
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .setTaskStatus(taskID, status, expectedVersion):
            try container.encode("set_task_status", forKey: .type)
            try container.encode(
                SetTaskStatus(
                    taskID: taskID,
                    status: status,
                    expectedVersion: expectedVersion
                ),
                forKey: .value
            )
        case let .rollback(targetRevision, reason):
            try container.encode("rollback", forKey: .type)
            try container.encode(
                Rollback(targetRevision: targetRevision, reason: reason),
                forKey: .value
            )
        }
    }
}

private struct RustPlanDepthSessionDTO: Decodable {
    let snapshot: RustPlanDepthSnapshotDTO
    let actorRole: String

    enum CodingKeys: String, CodingKey {
        case snapshot
        case actorRole = "actor_role"
    }
}

private struct RustPlanDepthSnapshotDTO: Decodable {
    let project: RustPlanProjectDTO
    let people: [RustPlanPersonDTO]
    let tasks: [RustPlanTaskDTO]
    let dependencies: [RustPlanDependencyDTO]
    let attachments: [RustPlanAttachmentDTO]
    let attachmentLinks: [RustPlanAttachmentLinkDTO]
    let history: [RustPlanHistoryDTO]

    enum CodingKeys: String, CodingKey {
        case project
        case people
        case tasks
        case dependencies
        case attachments
        case attachmentLinks = "attachment_links"
        case history
    }
}

private struct RustPlanProjectDTO: Decodable {
    let id: String
    let name: String
    let revision: UInt64
}

private struct RustPlanPersonDTO: Decodable {
    let id: String
    let name: String
    let initials: String
    let colorHex: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case initials
        case colorHex = "color_hex"
    }
}

private struct RustPlanTaskDTO: Decodable {
    let id: String
    let projectID: String
    let parentID: String?
    let title: String
    let descriptionMarkdown: String
    let status: String
    let priority: String
    let assigneeID: String?
    let startsOn: String
    let dueOn: String
    let estimateMinutes: UInt32
    let position: Int64
    let version: UInt64
    let completedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case projectID = "project_id"
        case parentID = "parent_id"
        case title
        case descriptionMarkdown = "description_markdown"
        case status
        case priority
        case assigneeID = "assignee_id"
        case startsOn = "starts_on"
        case dueOn = "due_on"
        case estimateMinutes = "estimate_minutes"
        case position
        case version
        case completedAt = "completed_at"
    }
}

private struct RustPlanDependencyDTO: Decodable {
    let taskID: String
    let dependsOnTaskID: String

    enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
        case dependsOnTaskID = "depends_on_task_id"
    }
}

private struct RustPlanAttachmentDTO: Decodable {
    let id: String
    let sha256: String
    let mediaType: String
    let byteSize: UInt64
    let filename: String

    enum CodingKeys: String, CodingKey {
        case id
        case sha256
        case mediaType = "media_type"
        case byteSize = "byte_size"
        case filename
    }
}

private struct RustPlanAttachmentLinkDTO: Decodable {
    let attachmentID: String
    let taskID: String

    enum CodingKeys: String, CodingKey {
        case attachmentID = "attachment_id"
        case taskID = "task_id"
    }
}

private struct RustPlanHistoryDTO: Decodable {
    let id: String
    let revision: UInt64
    let actorID: String
    let action: String
    let summary: String
    let occurredAt: String
    let restoredFromRevision: UInt64?
    let contentSHA256: String

    enum CodingKeys: String, CodingKey {
        case id
        case revision
        case actorID = "actor_id"
        case action
        case summary
        case occurredAt = "occurred_at"
        case restoredFromRevision = "restored_from_revision"
        case contentSHA256 = "content_sha256"
    }
}

private struct RustPlanReportDTO: Decodable {
    let sourceRevision: UInt64
    let generatedAt: String
    let range: RustPlanReportRangeDTO
    let tasks: [RustPlanReportTaskDTO]
    let statistics: RustPlanReportStatisticsDTO
    let html: String

    enum CodingKeys: String, CodingKey {
        case sourceRevision = "source_revision"
        case generatedAt = "generated_at"
        case range
        case tasks
        case statistics
        case html
    }
}

private struct RustPlanReportRangeDTO: Decodable {
    let startsOn: String
    let endsOn: String

    enum CodingKeys: String, CodingKey {
        case startsOn = "starts_on"
        case endsOn = "ends_on"
    }
}

private struct RustPlanReportTaskDTO: Decodable {
    let id: String
    let title: String
    let parentTitle: String?
    let status: String
    let priority: String
    let assigneeName: String?
    let startsOn: String
    let dueOn: String
    let estimateMinutes: UInt32
    let crossDay: Bool
    let overdue: Bool
    let dependencyCount: UInt32
    let subtaskCount: UInt32
    let attachmentCount: UInt32

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case parentTitle = "parent_title"
        case status
        case priority
        case assigneeName = "assignee_name"
        case startsOn = "starts_on"
        case dueOn = "due_on"
        case estimateMinutes = "estimate_minutes"
        case crossDay = "cross_day"
        case overdue
        case dependencyCount = "dependency_count"
        case subtaskCount = "subtask_count"
        case attachmentCount = "attachment_count"
    }
}

private struct RustPlanReportStatisticsDTO: Decodable {
    let taskCount: UInt32
    let completedCount: UInt32
    let overdueCount: UInt32
    let crossDayCount: UInt32
    let totalEstimateMinutes: UInt32

    enum CodingKeys: String, CodingKey {
        case taskCount = "task_count"
        case completedCount = "completed_count"
        case overdueCount = "overdue_count"
        case crossDayCount = "cross_day_count"
        case totalEstimateMinutes = "total_estimate_minutes"
    }
}
