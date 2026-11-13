import Foundation
import KshiftFFI

/// Production client adapter for the bounded C ABI in `kshift-ffi`.
///
/// The shared UI only sees `KshiftClientProtocol`. This type keeps the
/// protobuf and transport details below the Swift package boundary and maps
/// the FFI JSON projection into the presentation models used by the planner.
public final class RustClient: KshiftClientProtocol, @unchecked Sendable {
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
            let value = try JSONDecoder().decode(OfficialProjectSnapshot.self, from: data)
            return Self.mapSnapshot(value)
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
                    assigneeIDs: value.assigneeID.map { [$0] } ?? [],
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
                    assigneeIDs: value.assigneeID.map { [$0] } ?? [],
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
                    assigneeIDs: value.assigneeID.map { [$0] } ?? [],
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
            memberIDs: [],
            revision: value.currentRevision
        )
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
            memberIDs: members.map(\.id),
            revision: value.project.currentRevision
        )
        let tasks = value.tasks.enumerated().map { index, task in
            TaskItem(
                id: task.id,
                projectID: task.projectID,
                title: task.title,
                notes: task.descriptionMarkdown,
                status: mapStatus(task.status),
                priority: mapPriority(task.priority),
                assigneeID: task.assigneeIDs.first,
                dueDate: task.dueOn ?? task.plannedOn,
                position: Int64(index) * 1_024,
                version: task.version,
                updatedAt: task.updatedAt,
                updatedBy: task.updatedBy,
                history: []
            )
        }
        return ProjectSnapshot(project: project, people: members, tasks: tasks, audit: [])
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
    let currentRevision: UInt64

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case currentRevision = "current_revision"
    }
}

private struct OfficialProjectSnapshot: Decodable {
    let project: OfficialProject
    let members: [OfficialProjectMember]
    let tasks: [OfficialTask]
}

private struct OfficialProject: Decodable {
    let id: String
    let name: String
    let currentRevision: UInt64

    enum CodingKeys: String, CodingKey {
        case id
        case name
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
