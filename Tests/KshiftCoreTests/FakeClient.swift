import Foundation
@testable import KshiftCore

actor FakeKshiftClient: KshiftClientProtocol {
    nonisolated let actorID = "person-mia"
    private var projectValues: [ProjectSummary]
    private var snapshots: [String: ProjectSnapshot]
    private(set) var recordedEnvelopes: [CommandEnvelope] = []
    var nextResponse: CommandResponse?

    init(
        projects: [ProjectSummary],
        snapshots: [String: ProjectSnapshot]
    ) {
        self.projectValues = projects
        self.snapshots = snapshots
    }

    func projects() async throws -> [ProjectSummary] {
        projectValues
    }

    func snapshot(projectID: String) async throws -> ProjectSnapshot {
        guard let snapshot = snapshots[projectID] else {
            throw KshiftClientError.invalidResponse("missing snapshot")
        }
        return snapshot
    }

    func execute(projectID: String, envelope: CommandEnvelope) async throws -> CommandResponse {
        recordedEnvelopes.append(envelope)
        if let nextResponse {
            self.nextResponse = nil
            return nextResponse
        }
        guard let snapshot = snapshots[projectID] else {
            throw KshiftClientError.invalidResponse("missing snapshot")
        }
        return CommandResponse(
            ok: true,
            requestID: envelope.requestID,
            snapshot: snapshot,
            affectedTaskIDs: [],
            error: nil
        )
    }

    func setNextResponse(_ response: CommandResponse?) {
        nextResponse = response
    }
}

enum Fixture {
    static let people = [
        Person(id: "person-mia", name: "Mia Chen", initials: "MC", colorHex: "#0A84FF"),
        Person(id: "person-noah", name: "Noah Li", initials: "NL", colorHex: "#30D158"),
    ]

    static let focus = ProjectSummary(
        id: "project-focus",
        name: "Launch Room",
        code: "FOCUS",
        colorHex: "#0A84FF",
        timeZone: "Asia/Shanghai",
        memberIDs: people.map(\.id),
        revision: 8
    )

    static let customer = ProjectSummary(
        id: "project-customer",
        name: "Customer Follow-up",
        code: "CUSTOMER",
        colorHex: "#FF9F0A",
        timeZone: "Asia/Shanghai",
        memberIDs: people.map(\.id),
        revision: 3
    )

    static let date = "2026-11-13"

    static func task(
        id: String,
        projectID: String,
        title: String,
        notes: String = "",
        status: TaskStatus = .todo,
        priority: TaskPriority = .medium,
        assigneeIDs: [String] = ["person-mia"],
        dateValue: String = date,
        startValue: String? = nil,
        position: Int64 = 1024,
        tags: [String] = []
    ) -> TaskItem {
        TaskItem(
            id: id,
            projectID: projectID,
            title: title,
            notes: notes,
            status: status,
            priority: priority,
            assigneeIDs: assigneeIDs,
            dueDate: dateValue,
            startsOn: startValue,
            tags: tags,
            position: position,
            version: 1,
            updatedAt: "2026-11-13T02:00:00Z",
            updatedBy: "person-mia",
            history: []
        )
    }

    static let focusSnapshot = ProjectSnapshot(
        project: focus,
        people: people,
        tasks: [
            task(id: "task-1", projectID: focus.id, title: "Ship brief", priority: .high),
            task(id: "task-2", projectID: focus.id, title: "VoiceOver", status: .blocked, assigneeIDs: ["person-noah"], position: 2048),
            task(id: "task-3", projectID: focus.id, title: "Done item", status: .done, position: 3072),
            task(id: "task-4", projectID: focus.id, title: "Tomorrow", assigneeIDs: [], dateValue: "2026-11-14"),
        ],
        audit: []
    )

    static let customerSnapshot = ProjectSnapshot(
        project: customer,
        people: people,
        tasks: [
            task(id: "customer-1", projectID: customer.id, title: "Call customer"),
        ],
        audit: []
    )

    static func client() -> FakeKshiftClient {
        FakeKshiftClient(
            projects: [focus, customer],
            snapshots: [focus.id: focusSnapshot, customer.id: customerSnapshot]
        )
    }
}
