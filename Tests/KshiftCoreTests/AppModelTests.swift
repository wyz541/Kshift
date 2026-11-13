import XCTest
@testable import KshiftCore
@testable import KshiftUI
import KshiftPresentation

@MainActor
final class AppModelTests: XCTestCase {
    private func makeModel() -> (AppModel, FakeKshiftClient) {
        let client = Fixture.client()
        let model = AppModel(client: client, platform: KshiftNoopPlatformCapabilities(platform: .macOS))
        return (model, client)
    }

    func testBootstrapLoadsFirstProjectAndDailyBoard() async {
        let (model, _) = makeModel()
        await model.bootstrap()
        model.selectedDate = KshiftDate.date(from: Fixture.date) ?? .now

        XCTAssertEqual(model.projects.count, 2)
        XCTAssertEqual(model.selectedProject?.id, Fixture.focus.id)
        XCTAssertEqual(model.selectedDateTasks.count, 3)
        XCTAssertEqual(model.columns.count, 3)
        XCTAssertEqual(model.columns.first?.tasks.first?.title, "Ship brief")
        XCTAssertEqual(model.completedToday, 1)
        XCTAssertEqual(model.blockedToday, 1)
    }

    func testProjectSwitchKeepsDataIsolated() async {
        let (model, _) = makeModel()
        await model.bootstrap()
        await model.selectProject(Fixture.customer.id)
        model.selectedDate = KshiftDate.date(from: Fixture.date) ?? .now

        XCTAssertEqual(model.snapshot?.project.id, Fixture.customer.id)
        XCTAssertEqual(model.tasks.map(\.id), ["customer-1"])
        XCTAssertFalse(model.tasks.contains(where: { $0.projectID == Fixture.focus.id }))
    }

    func testSearchAndFiltersReduceDailyTasks() async {
        let (model, _) = makeModel()
        await model.bootstrap()
        model.selectedDate = KshiftDate.date(from: Fixture.date) ?? .now

        model.searchText = "voice"
        XCTAssertEqual(model.selectedDateTasks.map(\.id), ["task-2"])
        model.searchText = ""
        model.filter.assigneeIDs = ["person-noah"]
        XCTAssertEqual(model.selectedDateTasks.map(\.id), ["task-2"])
        model.filter.statuses = [.todo]
        XCTAssertTrue(model.selectedDateTasks.isEmpty)
    }

    func testCreateCommandUsesCurrentRevision() async {
        let (model, client) = makeModel()
        await model.bootstrap()
        let draft = TaskDraft(
            projectID: Fixture.focus.id,
            title: "New task",
            assigneeIDs: ["person-mia"],
            dueDate: KshiftDate.date(from: Fixture.date) ?? .now
        )

        let saved = await model.saveTask(draft)
        XCTAssertTrue(saved)
        let envelopes = await client.recordedEnvelopes
        XCTAssertEqual(envelopes.count, 1)
        XCTAssertEqual(envelopes[0].expectedRevision, 8)
        guard case let .create(command) = envelopes[0].command else {
            return XCTFail("Expected create command")
        }
        XCTAssertEqual(command.title, "New task")
        XCTAssertEqual(command.dueDate, Fixture.date)
    }

    func testConflictIsExplicitAndDoesNotReplaceSnapshot() async {
        let (model, client) = makeModel()
        await model.bootstrap()
        let before = model.snapshot
        await client.setNextResponse(
            CommandResponse(
                ok: false,
                requestID: "conflict-request",
                snapshot: nil,
                affectedTaskIDs: [],
                error: CommandError(
                    code: "version_conflict",
                    message: "任务已被其他编辑者修改。",
                    currentRevision: 9,
                    currentTaskVersion: 2,
                    taskID: "task-1"
                )
            )
        )

        let saved = await model.saveTask(
            TaskDraft(
                projectID: Fixture.focus.id,
                taskID: "task-1",
                expectedVersion: 1,
                title: "Locally edited",
                assigneeIDs: ["person-mia"],
                dueDate: KshiftDate.date(from: Fixture.date) ?? .now
            )
        )

        XCTAssertFalse(saved)
        XCTAssertEqual(model.conflict?.currentTaskVersion, 2)
        XCTAssertEqual(model.snapshot, before)
        XCTAssertEqual(model.task(withID: "task-1")?.title, "Ship brief")
    }

    func testMultiAssigneeFilterAndBoardColumnsUseAnyMatch() async {
        let sharedTask = Fixture.task(
            id: "shared-task",
            projectID: Fixture.focus.id,
            title: "Shared ownership",
            assigneeIDs: ["person-mia", "person-noah"]
        )
        let snapshot = ProjectSnapshot(
            project: Fixture.focus,
            people: Fixture.people,
            tasks: Fixture.focusSnapshot.tasks + [sharedTask],
            audit: []
        )
        let client = FakeKshiftClient(
            projects: [Fixture.focus],
            snapshots: [Fixture.focus.id: snapshot]
        )
        let model = AppModel(client: client, platform: KshiftNoopPlatformCapabilities(platform: .macOS))
        await model.bootstrap()
        model.selectedDate = KshiftDate.date(from: Fixture.date) ?? .now

        model.filter.assigneeIDs = ["person-noah"]
        XCTAssertTrue(model.filteredTasks.contains(where: { $0.id == sharedTask.id }))
        XCTAssertTrue(model.columns.first(where: { $0.id == "person-mia" })?.tasks.contains(where: { $0.id == sharedTask.id }) == true)
        XCTAssertTrue(model.columns.first(where: { $0.id == "person-noah" })?.tasks.contains(where: { $0.id == sharedTask.id }) == true)
    }
}
