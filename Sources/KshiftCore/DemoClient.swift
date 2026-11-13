import Foundation

/// Deterministic local data for Debug builds, previews, and UI evidence.
///
/// The production app uses `RustClient`. This client keeps the shared UI
/// runnable without a server while the authentication and project-selection
/// flow is not part of the R2 slice.
public actor DemoKshiftClient: KshiftClientProtocol {
    public nonisolated let actorID: String

    private var projects: [ProjectSummary]
    private var snapshots: [String: ProjectSnapshot]

    public init(actorID: String = "person-mia") {
        self.actorID = actorID
        let state = Self.makeState()
        self.projects = state.projects
        self.snapshots = state.snapshots
    }

    public func projects() async throws -> [ProjectSummary] {
        projects
    }

    public func snapshot(projectID: String) async throws -> ProjectSnapshot {
        guard let snapshot = snapshots[projectID] else {
            throw KshiftClientError.invalidResponse("项目不存在：\(projectID)")
        }
        return snapshot
    }

    public func execute(
        projectID: String,
        envelope: CommandEnvelope
    ) async throws -> CommandResponse {
        guard var snapshot = snapshots[projectID] else {
            throw KshiftClientError.invalidResponse("项目不存在：\(projectID)")
        }

        let nextRevision = snapshot.project.revision + 1
        let affected: [String]
        switch envelope.command {
        case let .create(command):
            let task = TaskItem(
                id: "task-\(UUID().uuidString.lowercased())",
                projectID: projectID,
                title: command.title,
                notes: command.notes,
                status: command.status,
                priority: command.priority,
                assigneeIDs: command.assigneeIDs,
                dueDate: command.dueDate,
                position: command.position ?? 1_024,
                version: 1,
                updatedAt: Self.timestamp,
                updatedBy: envelope.actorID,
                history: []
            )
            snapshot = replacing(snapshot, tasks: snapshot.tasks + [task], revision: nextRevision)
            affected = [task.id]
        case let .update(command):
            let tasks = snapshot.tasks.map { task in
                guard task.id == command.taskID else { return task }
                return TaskItem(
                    id: task.id,
                    projectID: task.projectID,
                    title: command.title,
                    notes: command.notes,
                    status: command.status,
                    priority: command.priority,
                    assigneeIDs: command.assigneeIDs,
                    dueDate: command.dueDate,
                    position: command.position,
                    version: task.version + 1,
                    updatedAt: Self.timestamp,
                    updatedBy: envelope.actorID,
                    history: task.history
                )
            }
            snapshot = replacing(snapshot, tasks: tasks, revision: nextRevision)
            affected = [command.taskID]
        case let .delete(taskID, _):
            snapshot = replacing(
                snapshot,
                tasks: snapshot.tasks.filter { $0.id != taskID },
                revision: nextRevision
            )
            affected = [taskID]
        case let .move(command):
            let tasks = snapshot.tasks.map { task in
                guard task.id == command.taskID else { return task }
                return TaskItem(
                    id: task.id,
                    projectID: task.projectID,
                    title: task.title,
                    notes: task.notes,
                    status: task.status,
                    priority: task.priority,
                    assigneeIDs: command.assigneeIDs,
                    dueDate: command.dueDate,
                    position: command.position,
                    version: task.version + 1,
                    updatedAt: Self.timestamp,
                    updatedBy: envelope.actorID,
                    history: task.history
                )
            }
            snapshot = replacing(snapshot, tasks: tasks, revision: nextRevision)
            affected = [command.taskID]
        case let .setStatus(command):
            let items = Dictionary(uniqueKeysWithValues: command.items.map { ($0.taskID, $0.expectedTaskVersion) })
            let tasks = snapshot.tasks.map { task in
                guard items[task.id] != nil else { return task }
                return TaskItem(
                    id: task.id,
                    projectID: task.projectID,
                    title: task.title,
                    notes: task.notes,
                    status: command.status,
                    priority: task.priority,
                    assigneeIDs: task.assigneeIDs,
                    dueDate: task.dueDate,
                    position: task.position,
                    version: task.version + 1,
                    updatedAt: Self.timestamp,
                    updatedBy: envelope.actorID,
                    history: task.history
                )
            }
            snapshot = replacing(snapshot, tasks: tasks, revision: nextRevision)
            affected = command.items.map(\.taskID)
        }

        snapshots[projectID] = snapshot
        if let index = projects.firstIndex(where: { $0.id == projectID }) {
            projects[index] = snapshot.project
        }
        return CommandResponse(
            ok: true,
            requestID: envelope.requestID,
            snapshot: snapshot,
            affectedTaskIDs: affected,
            error: nil
        )
    }

    private func replacing(
        _ snapshot: ProjectSnapshot,
        tasks: [TaskItem],
        revision: UInt64
    ) -> ProjectSnapshot {
        let project = ProjectSummary(
            id: snapshot.project.id,
            name: snapshot.project.name,
            code: snapshot.project.code,
            colorHex: snapshot.project.colorHex,
            timeZone: snapshot.project.timeZone,
            memberIDs: snapshot.project.memberIDs,
            revision: revision
        )
        return ProjectSnapshot(
            project: project,
            people: snapshot.people,
            tasks: tasks,
            audit: snapshot.audit
        )
    }

    private static let timestamp = "2026-11-13T02:00:00Z"

    private static func makeState() -> (projects: [ProjectSummary], snapshots: [String: ProjectSnapshot]) {
        let today = KshiftDate.isoString(from: .now)
        let tomorrow = KshiftDate.isoString(from: KshiftDate.addingDays(1, to: .now))
        let people = [
            Person(id: "person-mia", name: "Mia Chen", initials: "MC", colorHex: "#0A84FF"),
            Person(id: "person-noah", name: "Noah Li", initials: "NL", colorHex: "#30D158"),
        ]
        let focus = ProjectSummary(
            id: "project-focus",
            name: "Launch Room",
            code: "FOCUS",
            colorHex: "#0A84FF",
            timeZone: "Asia/Shanghai",
            memberIDs: people.map(\.id),
            revision: 8
        )
        let customer = ProjectSummary(
            id: "project-customer",
            name: "Customer Follow-up",
            code: "CUSTOMER",
            colorHex: "#FF9F0A",
            timeZone: "Asia/Shanghai",
            memberIDs: people.map(\.id),
            revision: 3
        )
        let focusTasks = [
            task(id: "task-launch-brief", projectID: focus.id, title: "Ship brief", priority: .high, date: today),
            task(id: "task-voiceover", projectID: focus.id, title: "VoiceOver", status: .blocked, assigneeIDs: ["person-noah"], date: today, position: 2_048),
            task(id: "task-done", projectID: focus.id, title: "Done item", status: .done, date: today, position: 3_072),
            task(id: "task-tomorrow", projectID: focus.id, title: "Tomorrow", assigneeIDs: [], date: tomorrow),
        ]
        let customerTasks = [
            task(id: "customer-task", projectID: customer.id, title: "Call customer", date: today),
        ]
        return (
            [focus, customer],
            [
                focus.id: ProjectSnapshot(project: focus, people: people, tasks: focusTasks, audit: []),
                customer.id: ProjectSnapshot(project: customer, people: people, tasks: customerTasks, audit: []),
            ]
        )
    }

    private static func task(
        id: String,
        projectID: String,
        title: String,
        status: TaskStatus = .todo,
        priority: TaskPriority = .medium,
        assigneeIDs: [String] = ["person-mia"],
        date: String,
        position: Int64 = 1_024
    ) -> TaskItem {
        TaskItem(
            id: id,
            projectID: projectID,
            title: title,
            notes: "",
            status: status,
            priority: priority,
            assigneeIDs: assigneeIDs,
            dueDate: date,
            position: position,
            version: 1,
            updatedAt: timestamp,
            updatedBy: "person-mia",
            history: []
        )
    }
}

public enum KshiftClientFactory {
    public static func makeDefault(actorID: String = "person-mia") -> any KshiftClientProtocol {
        let environment = ProcessInfo.processInfo.environment
        if environment["KSHIFT_USE_FFI"] == "1" {
            return RustClient(actorID: actorID)
        }
        if environment["KSHIFT_DEMO_MODE"] == "1" {
            return DemoKshiftClient(actorID: actorID)
        }
#if DEBUG
        return DemoKshiftClient(actorID: actorID)
#else
        return RustClient(actorID: actorID)
#endif
    }
}
