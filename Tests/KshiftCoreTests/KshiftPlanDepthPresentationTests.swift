import XCTest
@testable import KshiftPresentation

final class KshiftPlanDepthPresentationTests: XCTestCase {
    private let mapper = KshiftPlanDepthPresentationMapper(
        locale: Locale(identifier: "zh_Hans_CN"),
        timeZone: TimeZone(secondsFromGMT: 0)!
    )

    func testBoardCapsNativeGlassCardsAtSix() {
        let snapshot = KshiftPlanSampleData.makeSnapshot()
        let presentation = mapper.makePresentation(
            snapshot: snapshot,
            filter: KshiftPlanDepthFilter(),
            viewerRole: .admin
        )
        let visibleTasks = presentation.columns.flatMap(\.tasks)
        XCTAssertLessThanOrEqual(
            visibleTasks.count,
            KshiftPlanDepthPresentationMapper.maximumVisibleInteractiveCards
        )
        XCTAssertGreaterThan(presentation.hiddenTaskCount, 0)
    }

    func testBoardColumnTotalsIncludeHiddenTasks() {
        let snapshot = KshiftPlanSampleData.makeSnapshot()
        let presentation = mapper.makePresentation(
            snapshot: snapshot,
            filter: KshiftPlanDepthFilter(),
            viewerRole: .admin
        )
        XCTAssertEqual(
            presentation.columns.reduce(0) { $0 + $1.totalCount },
            snapshot.tasks.count
        )
        XCTAssertEqual(
            presentation.columns.first { $0.status == .done }?.totalCount,
            snapshot.tasks.filter { $0.status == .done }.count
        )
        XCTAssertEqual(
            presentation.columns.reduce(0) { $0 + $1.tasks.count },
            KshiftPlanDepthPresentationMapper.maximumVisibleInteractiveCards
        )
    }

    func testGanttFractionsStayInsideWindowAndMarkCrossDayTasks() {
        let snapshot = KshiftPlanSampleData.makeSnapshot()
        let presentation = mapper.makePresentation(
            snapshot: snapshot,
            filter: KshiftPlanDepthFilter(),
            viewerRole: .editor
        )
        XCTAssertFalse(presentation.gantt.rows.isEmpty)
        for row in presentation.gantt.rows {
            XCTAssertGreaterThanOrEqual(row.startFraction, 0)
            XCTAssertLessThanOrEqual(row.startFraction + row.widthFraction, 1.000_001)
        }
        XCTAssertTrue(presentation.gantt.rows.contains { $0.crossDay })
    }

    func testSearchAndAssigneeFilterUseOneSnapshot() {
        let snapshot = KshiftPlanSampleData.makeSnapshot()
        let presentation = mapper.makePresentation(
            snapshot: snapshot,
            filter: KshiftPlanDepthFilter(
                searchText: "依赖环检测",
                assigneeID: KshiftPlanSampleData.zhouID
            ),
            viewerRole: .editor
        )
        let tasks = presentation.columns.flatMap(\.tasks)
        XCTAssertEqual(tasks.map(\.title), ["补齐依赖环检测"])
        XCTAssertEqual(presentation.revisionLabel, "r7")
    }

    func testReportPrintAndImageShareSourceRevision() async throws {
        let snapshot = KshiftPlanSampleData.makeSnapshot()
        let boundary = InMemoryKshiftPlanDepthBoundary(snapshot: snapshot)
        let calendar = Calendar(identifier: .gregorian)
        let range = KshiftReportRange(
            startsOn: calendar.date(byAdding: .day, value: -3, to: .now)!,
            endsOn: calendar.date(byAdding: .day, value: 7, to: .now)!
        )
        let report = try await boundary.fetchReport(
            projectID: snapshot.projectID,
            range: range
        )
        let presentation = mapper.makeReportPresentation(report)
        XCTAssertEqual(report.sourceRevision, snapshot.revision)
        XCTAssertEqual(presentation.sourceRevision, snapshot.revision)
        XCTAssertTrue(presentation.html.contains("revision \(snapshot.revision)"))
        XCTAssertEqual(report.tasks.count, presentation.rows.count)
    }
}
