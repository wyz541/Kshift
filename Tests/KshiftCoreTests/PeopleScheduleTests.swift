import XCTest
@testable import KshiftCore
@testable import KshiftUI
import KshiftPresentation

@MainActor
final class PeopleScheduleTests: XCTestCase {
    private let fixtureDate = "2026-11-13"

    func testPeopleScheduleIsDefaultWithoutSavedViewMode() async throws {
        let context = try makeContext()
        defer { context.cleanup() }

        let model = context.model()
        XCTAssertEqual(model.viewMode, .peopleSchedule)

        await model.bootstrap()

        XCTAssertEqual(model.viewMode, .peopleSchedule)
        XCTAssertEqual(model.schedulePeriod, .week)
        XCTAssertEqual(model.scheduleDensity, .compact)
        XCTAssertEqual(model.schedulePeopleColumnWidth, 196)
        XCTAssertEqual(model.scheduleDateColumnWidth, 96)
    }

    func testExplicitViewModeIsRestoredPerProject() async throws {
        let context = try makeContext()
        defer { context.cleanup() }

        let first = context.model()
        await first.bootstrap()
        first.viewMode = .board

        let restored = context.model()
        await restored.bootstrap()
        XCTAssertEqual(restored.viewMode, .board)

        await restored.selectProject(Fixture.customer.id)
        XCTAssertEqual(restored.viewMode, .peopleSchedule)
    }

    func testScheduleStateIsRestoredPerProject() async throws {
        let context = try makeContext()
        defer { context.cleanup() }

        let first = context.model()
        await first.bootstrap()
        first.schedulePeriod = .month
        first.scheduleDensity = .comfortable
        first.setSchedulePeopleColumnWidth(240)
        first.setScheduleDateColumnWidth(320)
        first.selectDate(try XCTUnwrap(FixtureDate.date(from: "2026-11-18", calendar: first.projectCalendar)))
        first.setScheduleScrollAnchor(try XCTUnwrap(FixtureDate.date(from: "2026-11-20", calendar: first.projectCalendar)))
        first.toggleSchedulePersonCollapsed("person-noah")

        let restored = context.model()
        await restored.bootstrap()

        XCTAssertEqual(restored.schedulePeriod, .month)
        XCTAssertEqual(restored.scheduleDensity, .comfortable)
        XCTAssertEqual(restored.schedulePeopleColumnWidth, 240)
        XCTAssertEqual(restored.scheduleDateColumnWidth, 320)
        XCTAssertEqual(restored.selectedDateString, "2026-11-18")
        XCTAssertEqual(restored.scheduleScrollAnchorDayID, "2026-11-20")
        XCTAssertTrue(restored.collapsedSchedulePersonIDs.contains("person-noah"))
    }

    func testScheduleColumnWidthsClampToSpecifiedBounds() async throws {
        let context = try makeContext()
        defer { context.cleanup() }

        let model = context.model()
        await model.bootstrap()
        model.setScheduleDateColumnWidth(1)
        XCTAssertEqual(model.scheduleDateColumnWidth, 96)
        model.setScheduleDateColumnWidth(999)
        XCTAssertEqual(model.scheduleDateColumnWidth, 360)
        model.setSchedulePeopleColumnWidth(1)
        XCTAssertEqual(model.schedulePeopleColumnWidth, 168)
        model.setSchedulePeopleColumnWidth(999)
        XCTAssertEqual(model.schedulePeopleColumnWidth, 320)
    }

    func testWeekMonthAndPeriodNavigationUseProjectCalendar() async throws {
        let context = try makeContext()
        defer { context.cleanup() }
        let model = context.model()
        await model.bootstrap()
        model.selectDate(try XCTUnwrap(FixtureDate.date(from: fixtureDate, calendar: model.projectCalendar)))

        XCTAssertEqual(model.scheduleDays.count, 7)
        model.setSchedulePeriod(.month)
        XCTAssertEqual(model.scheduleDays.count, 30)
        XCTAssertEqual(model.projectCalendar.component(.month, from: model.scheduleRangeStart), 11)

        model.moveSchedulePeriod(1)
        XCTAssertEqual(model.scheduleDays.count, 31)
        XCTAssertEqual(model.projectCalendar.component(.month, from: model.scheduleRangeStart), 12)
    }

    func testLaneAllocationReusesTracksAndKeepsOverlapsSeparate() throws {
        let calendar = projectCalendar
        let days = makeDays(start: "2026-11-01", count: 10, calendar: calendar)
        let tasks = [
            task(id: "a", title: "A", start: "2026-11-01", due: "2026-11-03"),
            task(id: "b", title: "B", start: "2026-11-02", due: "2026-11-02", priority: .high),
            task(id: "c", title: "C", start: "2026-11-04", due: "2026-11-04", priority: .low),
        ]

        let slices = PeopleScheduleLayout.slices(for: tasks, days: days, calendar: calendar)
        let lanes = Dictionary(uniqueKeysWithValues: slices.map { ($0.task.id, $0.lane) })

        XCTAssertEqual(lanes["a"], 0)
        XCTAssertEqual(lanes["b"], 1)
        XCTAssertEqual(lanes["c"], 0)
        XCTAssertEqual(PeopleScheduleLayout.laneCount(for: slices), 2)
    }

    func testPriorityAndStatusOrderingWithinSameStartDay() throws {
        let calendar = projectCalendar
        let days = makeDays(start: "2026-11-01", count: 4, calendar: calendar)
        let tasks = [
            task(id: "done", title: "Done", start: "2026-11-01", due: "2026-11-01", status: .done),
            task(id: "todo", title: "Todo", start: "2026-11-01", due: "2026-11-01", status: .todo),
            task(id: "blocked", title: "Blocked", start: "2026-11-01", due: "2026-11-01", status: .blocked),
            task(id: "urgent", title: "Urgent", start: "2026-11-01", due: "2026-11-01", priority: .urgent),
        ]

        let slices = PeopleScheduleLayout.slices(for: tasks, days: days, calendar: calendar)
        XCTAssertEqual(slices.map(\.task.id), ["urgent", "blocked", "todo", "done"])
    }

    func testStickyTitleMovesFromTaskStartToViewportEdge() {
        let fullyVisible = PeopleScheduleLayout.stickyTitleLeading(
            taskStartIndex: 2,
            dateColumnWidth: 120,
            taskWidth: 240,
            horizontalOffset: 100,
            viewportWidth: 700
        )
        let clippedLeft = PeopleScheduleLayout.stickyTitleLeading(
            taskStartIndex: 2,
            dateColumnWidth: 120,
            taskWidth: 480,
            horizontalOffset: 300,
            viewportWidth: 700
        )

        XCTAssertEqual(fullyVisible, 8)
        XCTAssertEqual(clippedLeft, 68)
    }

    func testHiddenSuccessorMarkersAreAtMostOnePerLaneAndMutuallyExclusive() throws {
        let calendar = projectCalendar
        let days = makeDays(start: "2026-11-01", count: 10, calendar: calendar)
        let slices = PeopleScheduleLayout.slices(
            for: [
                task(id: "later", title: "Later", start: "2026-11-08", due: "2026-11-08"),
            ],
            days: days,
            calendar: calendar
        )

        let hiddenMarkers = PeopleScheduleLayout.hiddenSuccessorMarkers(
            in: slices,
            visibleStartIndex: 0,
            visibleEndIndex: 2
        )
        XCTAssertEqual(hiddenMarkers[0]?.task.id, "later")

        let visibleSlices = PeopleScheduleLayout.slices(
            for: [
                task(id: "visible", title: "Visible", start: "2026-11-01", due: "2026-11-01"),
                task(id: "later", title: "Later", start: "2026-11-08", due: "2026-11-08"),
            ],
            days: days,
            calendar: calendar
        )
        let mutuallyExclusiveMarkers = PeopleScheduleLayout.hiddenSuccessorMarkers(
            in: visibleSlices,
            visibleStartIndex: 0,
            visibleEndIndex: 2
        )
        XCTAssertTrue(mutuallyExclusiveMarkers.isEmpty)
    }

    func testSearchMatchesDescriptionAndTagsAndTagFilterNarrowsResults() async throws {
        let calendar = projectCalendar
        let tagged = task(
            id: "tagged",
            title: "Release checklist",
            notes: "legal approval required",
            start: fixtureDate,
            due: fixtureDate,
            tags: ["launch", "approval"]
        )
        let snapshot = ProjectSnapshot(
            project: Fixture.focus,
            people: Fixture.people,
            tasks: [tagged],
            audit: []
        )
        let client = FakeKshiftClient(
            projects: [Fixture.focus],
            snapshots: [Fixture.focus.id: snapshot]
        )
        let model = contextModel(client: client)

        await model.bootstrap()
        XCTAssertEqual(model.selectedDateString, fixtureDate)
        model.searchText = "legal"
        XCTAssertEqual(model.filteredTasks.map(\.id), ["tagged"])
        model.searchText = "launch"
        XCTAssertEqual(model.filteredTasks.map(\.id), ["tagged"])
        model.searchText = ""
        model.filter.tags = ["approval"]
        XCTAssertEqual(model.filteredTasks.map(\.id), ["tagged"])
        model.filter.tags = ["missing"]
        XCTAssertTrue(model.filteredTasks.isEmpty)
        XCTAssertEqual(calendar.timeZone.identifier, "Asia/Shanghai")
    }

    func testMoveScheduleTaskUpdatesAssigneeAndPreservesDuration() async throws {
        let calendar = projectCalendar
        let taskValue = task(
            id: "multi-day",
            title: "Multi-day",
            start: "2026-11-13",
            due: "2026-11-15"
        )
        let snapshot = ProjectSnapshot(
            project: Fixture.focus,
            people: Fixture.people,
            tasks: [taskValue],
            audit: []
        )
        let client = FakeKshiftClient(
            projects: [Fixture.focus],
            snapshots: [Fixture.focus.id: snapshot]
        )
        let model = contextModel(client: client)
        await model.bootstrap()

        await model.moveScheduleTask(
            taskID: "multi-day",
            toAssigneeID: "person-noah",
            date: try XCTUnwrap(FixtureDate.date(from: "2026-11-16", calendar: calendar))
        )

        let envelopes = await client.recordedEnvelopes
        guard case let .move(command) = try XCTUnwrap(envelopes.last?.command) else {
            return XCTFail("Expected move command")
        }
        XCTAssertEqual(command.assigneeIDs, ["person-noah"])
        XCTAssertEqual(command.startDate, "2026-11-16")
        XCTAssertEqual(command.dueDate, "2026-11-18")
    }

    func testResizeScheduleTaskClampsCrossDayInvariant() async throws {
        let calendar = projectCalendar
        let taskValue = task(
            id: "resize",
            title: "Resize",
            start: "2026-11-13",
            due: "2026-11-15"
        )
        let snapshot = ProjectSnapshot(
            project: Fixture.focus,
            people: Fixture.people,
            tasks: [taskValue],
            audit: []
        )
        let client = FakeKshiftClient(
            projects: [Fixture.focus],
            snapshots: [Fixture.focus.id: snapshot]
        )
        let model = contextModel(client: client)
        await model.bootstrap()

        await model.resizeScheduleTask(
            taskID: "resize",
            edge: .start,
            date: try XCTUnwrap(FixtureDate.date(from: "2026-11-20", calendar: calendar))
        )
        var envelopes = await client.recordedEnvelopes
        guard case let .move(startCommand) = try XCTUnwrap(envelopes.last?.command) else {
            return XCTFail("Expected move command")
        }
        XCTAssertEqual(startCommand.startDate, "2026-11-15")
        XCTAssertEqual(startCommand.dueDate, "2026-11-15")

        await model.resizeScheduleTask(
            taskID: "resize",
            edge: .end,
            date: try XCTUnwrap(FixtureDate.date(from: "2026-11-10", calendar: calendar))
        )
        envelopes = await client.recordedEnvelopes
        guard case let .move(endCommand) = try XCTUnwrap(envelopes.last?.command) else {
            return XCTFail("Expected move command")
        }
        XCTAssertEqual(endCommand.startDate, "2026-11-13")
        XCTAssertEqual(endCommand.dueDate, "2026-11-13")
    }

    func testLargeScheduleDatasetLaysOutFiftyPeopleThirtyDaysTwentyTasksEach() {
        let calendar = projectCalendar
        let days = makeDays(start: "2026-11-01", count: 30, calendar: calendar)
        var totalSlices = 0

        for personIndex in 0..<50 {
            let tasks = (0..<20).map { taskIndex in
                let startOffset = taskIndex % 24
                let duration = (taskIndex % 4) + 1
                let start = KshiftDate.isoString(
                    from: days[startOffset],
                    calendar: calendar
                )
                let due = KshiftDate.isoString(
                    from: calendar.date(
                        byAdding: .day,
                        value: duration - 1,
                        to: days[startOffset]
                    ) ?? days[startOffset],
                    calendar: calendar
                )
                return task(
                    id: "person-\(personIndex)-task-\(taskIndex)",
                    title: "Task \(personIndex)-\(taskIndex)",
                    start: start,
                    due: due,
                    priority: TaskPriority.allCases[taskIndex % TaskPriority.allCases.count]
                )
            }
            totalSlices += PeopleScheduleLayout.slices(
                for: tasks,
                days: days,
                calendar: calendar
            ).count
        }

        XCTAssertEqual(totalSlices, 1_000)
    }

    func testMarkerFocusMovesPeriodAndScrollAnchorToTaskStart() async throws {
        let context = try makeContext()
        defer { context.cleanup() }
        let model = context.model()
        await model.bootstrap()
        model.selectDate(try XCTUnwrap(FixtureDate.date(from: "2026-11-13", calendar: model.projectCalendar)))

        let futureTask = task(
            id: "future",
            title: "Future task",
            start: "2026-12-03",
            due: "2026-12-05"
        )
        model.focusSchedule(on: futureTask)

        XCTAssertEqual(model.selectedDateString, "2026-12-03")
        XCTAssertEqual(model.scheduleScrollAnchorDayID, "2026-12-03")
        XCTAssertTrue(model.scheduleDays.contains {
            KshiftDate.isoString(from: $0, calendar: model.projectCalendar) == "2026-12-03"
        })
    }

    private var projectCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt
        return calendar
    }

    private func makeContext() throws -> TestContext {
        let suiteName = "PeopleScheduleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let now = try XCTUnwrap(FixtureDate.date(from: fixtureDate, calendar: projectCalendar))
        return TestContext(
            suiteName: suiteName,
            defaults: defaults,
            now: now,
            projectCalendar: projectCalendar
        )
    }

    private func contextModel(client: FakeKshiftClient? = nil) -> AppModel {
        let defaults = UserDefaults(suiteName: "PeopleScheduleTests.search.\(UUID().uuidString)")!
        return AppModel(
            client: client ?? Fixture.client(),
            platform: KshiftNoopPlatformCapabilities(platform: .macOS),
            now: { FixtureDate.date(from: self.fixtureDate, calendar: self.projectCalendar) ?? .now },
            preferencesStore: PlannerViewPreferencesStore(defaults: defaults)
        )
    }

    private func makeDays(start: String, count: Int, calendar: Calendar) -> [Date] {
        let startDate = FixtureDate.date(from: start, calendar: calendar)!
        return (0..<count).map {
            calendar.date(byAdding: .day, value: $0, to: startDate)!
        }
    }

    private func task(
        id: String,
        title: String,
        notes: String = "",
        start: String,
        due: String,
        status: TaskStatus = .todo,
        priority: TaskPriority = .medium,
        tags: [String] = []
    ) -> TaskItem {
        Fixture.task(
            id: id,
            projectID: Fixture.focus.id,
            title: title,
            notes: notes,
            status: status,
            priority: priority,
            dateValue: due,
            startValue: start,
            tags: tags
        )
    }

    private struct TestContext {
        let suiteName: String
        let defaults: UserDefaults
        let now: Date
        let projectCalendar: Calendar

        @MainActor
        func model() -> AppModel {
            AppModel(
                client: Fixture.client(),
                platform: KshiftNoopPlatformCapabilities(platform: .macOS),
                now: { now },
                preferencesStore: PlannerViewPreferencesStore(defaults: defaults)
            )
        }

        func cleanup() {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    private typealias FixtureDate = KshiftDate
}
