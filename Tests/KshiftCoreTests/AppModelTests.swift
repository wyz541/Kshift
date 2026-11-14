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
        model.selectDate(KshiftDate.date(from: Fixture.date, calendar: model.projectCalendar) ?? .now)

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
        model.selectDate(KshiftDate.date(from: Fixture.date, calendar: model.projectCalendar) ?? .now)

        XCTAssertEqual(model.snapshot?.project.id, Fixture.customer.id)
        XCTAssertEqual(model.tasks.map(\.id), ["customer-1"])
        XCTAssertFalse(model.tasks.contains(where: { $0.projectID == Fixture.focus.id }))
    }

    func testSelectProjectLoadsSnapshotWhenSelectionWasAlreadyUpdated() async {
        let (model, _) = makeModel()
        await model.bootstrap()
        model.selectedProjectID = Fixture.customer.id

        await model.selectProject(Fixture.customer.id)

        XCTAssertEqual(model.snapshot?.project.id, Fixture.customer.id)
        XCTAssertEqual(model.tasks.map(\.id), ["customer-1"])
        XCTAssertEqual(model.selectedProjectID, Fixture.customer.id)
    }

    func testSearchAndFiltersReduceDailyTasks() async {
        let (model, _) = makeModel()
        await model.bootstrap()
        model.selectDate(KshiftDate.date(from: Fixture.date, calendar: model.projectCalendar) ?? .now)

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
            dueDate: KshiftDate.date(from: Fixture.date, calendar: model.projectCalendar) ?? .now
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
                dueDate: KshiftDate.date(from: Fixture.date, calendar: model.projectCalendar) ?? .now
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
        model.selectDate(KshiftDate.date(from: Fixture.date, calendar: model.projectCalendar) ?? .now)

        model.filter.assigneeIDs = ["person-noah"]
        XCTAssertTrue(model.filteredTasks.contains(where: { $0.id == sharedTask.id }))
        XCTAssertTrue(model.columns.first(where: { $0.id == "person-mia" })?.tasks.contains(where: { $0.id == sharedTask.id }) == true)
        XCTAssertTrue(model.columns.first(where: { $0.id == "person-noah" })?.tasks.contains(where: { $0.id == sharedTask.id }) == true)
    }

    func testProjectTimeZoneControlsTodayDateSelectionAndDailyCounts() async throws {
        let now = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-11-14T10:30:00Z")
        )
        let project = ProjectSummary(
            id: "project-kiritimati",
            name: "Kiritimati",
            code: "KIRI",
            colorHex: "#0A84FF",
            timeZone: "Pacific/Kiritimati",
            memberIDs: ["person-mia"],
            revision: 1
        )
        let person = Person(
            id: "person-mia",
            name: "Mia Chen",
            initials: "MC",
            colorHex: "#0A84FF"
        )
        let snapshot = ProjectSnapshot(
            project: project,
            people: [person],
            tasks: [
                Fixture.task(
                    id: "kiritimati-task",
                    projectID: project.id,
                    title: "Project date task",
                    dateValue: "2026-11-15"
                ),
            ],
            audit: []
        )
        let client = FakeKshiftClient(
            projects: [project],
            snapshots: [project.id: snapshot]
        )
        let model = AppModel(
            client: client,
            platform: KshiftNoopPlatformCapabilities(platform: .macOS),
            userTimeZone: TimeZone(identifier: "America/Los_Angeles"),
            now: { now }
        )

        await model.bootstrap()

        XCTAssertEqual(model.selectedDateString, "2026-11-15")
        XCTAssertEqual(model.selectedDateTasks.map(\.id), ["kiritimati-task"])
        XCTAssertEqual(model.taskCount(on: model.selectedDate), 1)
        XCTAssertTrue(model.isProjectToday(model.selectedDate))

        model.addDaysToSelection(1)
        XCTAssertEqual(model.selectedDateString, "2026-11-16")
        model.selectToday()
        XCTAssertEqual(model.selectedDateString, "2026-11-15")
    }

    func testProjectSwitchUsesEachProjectTimeZoneForToday() async throws {
        let now = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-11-14T10:30:00Z")
        )
        let alpha = ProjectSummary(
            id: "project-alpha",
            name: "Alpha",
            code: "ALPHA",
            colorHex: "#0A84FF",
            timeZone: "Pacific/Kiritimati",
            memberIDs: ["person-mia"],
            revision: 1
        )
        let beta = ProjectSummary(
            id: "project-beta",
            name: "Beta",
            code: "BETA",
            colorHex: "#FF9F0A",
            timeZone: "America/Los_Angeles",
            memberIDs: ["person-mia"],
            revision: 1
        )
        let person = Person(
            id: "person-mia",
            name: "Mia Chen",
            initials: "MC",
            colorHex: "#0A84FF"
        )
        let snapshots = [
            alpha.id: ProjectSnapshot(project: alpha, people: [person], tasks: [], audit: []),
            beta.id: ProjectSnapshot(project: beta, people: [person], tasks: [], audit: []),
        ]
        let model = AppModel(
            client: FakeKshiftClient(projects: [alpha, beta], snapshots: snapshots),
            platform: KshiftNoopPlatformCapabilities(platform: .macOS),
            userTimeZone: TimeZone(identifier: "Asia/Shanghai"),
            now: { now }
        )

        await model.bootstrap()
        XCTAssertEqual(model.selectedDateString, "2026-11-15")

        await model.selectProject(beta.id)
        XCTAssertEqual(model.selectedDateString, "2026-11-14")

        await model.selectProject(alpha.id)
        XCTAssertEqual(model.selectedDateString, "2026-11-15")
    }

    func testInvalidUserTimeZoneFallsBackToProjectTimeZone() async throws {
        let project = ProjectSummary(
            id: "project-fallback",
            name: "Fallback",
            code: "FALLBACK",
            colorHex: "#0A84FF",
            timeZone: "Pacific/Kiritimati",
            memberIDs: ["person-mia"],
            revision: 1
        )
        let person = Person(
            id: "person-mia",
            name: "Mia Chen",
            initials: "MC",
            colorHex: "#0A84FF"
        )
        let snapshot = ProjectSnapshot(project: project, people: [person], tasks: [], audit: [])
        let model = AppModel(
            client: FakeKshiftClient(projects: [project], snapshots: [project.id: snapshot]),
            platform: KshiftNoopPlatformCapabilities(platform: .macOS),
            userTimeZone: nil,
            fallbackUserTimeZoneToProject: true
        )

        await model.bootstrap()

        XCTAssertEqual(model.userTimeZone, model.projectTimeZone)
        XCTAssertEqual(model.userTimeZone.identifier, "Pacific/Kiritimati")
    }
}
