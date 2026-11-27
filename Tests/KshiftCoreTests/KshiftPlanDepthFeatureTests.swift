import XCTest
@testable import KshiftPresentation
@testable import KshiftUI

@MainActor
final class KshiftPlanDepthFeatureTests: XCTestCase {
    func testReportImageExportUsesTypedReportRevision() async throws {
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
        let image = KshiftReportExporter.renderPNG(report: report)
        XCTAssertNotNil(image)
        XCTAssertEqual(image.map { Array($0.prefix(8)) }, [137, 80, 78, 71, 13, 10, 26, 10])
        XCTAssertEqual(report.sourceRevision, snapshot.revision)
        XCTAssertTrue(report.html.contains("revision \(report.sourceRevision)"))
    }

    func testFeatureModelRejectsStaleRevision() async {
        let boundary = KshiftPlanSampleData.makeBoundary()
        let capabilities = KshiftNoopPlatformCapabilities()
        let model = KshiftPlanDepthFeatureModel(
            boundary: boundary,
            capabilities: capabilities
        )
        await model.load()
        guard let task = model.snapshot?.tasks.first else {
            return XCTFail("sample task missing")
        }
        _ = try? await boundary.execute(
            projectID: KshiftPlanSampleData.projectID,
            .setTaskStatus(
                taskID: task.id,
                status: task.status == .done ? .todo : .done,
                expectedTaskVersion: task.version,
                expectedRevision: model.snapshot!.revision
            )
        )
        do {
            _ = try await boundary.execute(
                projectID: KshiftPlanSampleData.projectID,
                .setTaskStatus(
                    taskID: task.id,
                    status: .done,
                    expectedTaskVersion: task.version,
                    expectedRevision: model.snapshot!.revision
                )
            )
            XCTFail("stale revision must fail")
        } catch let error as KshiftPlanDepthError {
            guard case .revisionConflict = error else {
                return XCTFail("unexpected error: \(error)")
            }
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testFeatureModelReschedulePersistsAuditEventAndPresentation() async throws {
        let boundary = KshiftPlanSampleData.makeBoundary()
        let capabilities = KshiftNoopPlatformCapabilities()
        let model = KshiftPlanDepthFeatureModel(
            boundary: boundary,
            capabilities: capabilities
        )
        await model.load()
        let task = try XCTUnwrap(
            model.snapshot?.tasks.first { $0.id == KshiftPlanSampleData.planTaskID }
        )
        let countBefore = model.snapshot?.reschedules.count ?? 0
        let calendar = Calendar(identifier: .gregorian)
        let newDue = try XCTUnwrap(calendar.date(byAdding: .day, value: 2, to: task.dueOn))

        let succeeded = await model.reschedule(
            taskID: task.id,
            startsOn: task.startsOn,
            dueOn: newDue,
            reason: "等待接口联调"
        )

        XCTAssertTrue(succeeded)
        let updated = try XCTUnwrap(
            model.snapshot?.tasks.first { $0.id == task.id }
        )
        XCTAssertEqual(updated.dueOn, newDue)
        XCTAssertEqual(updated.version, task.version + 1)
        XCTAssertEqual(model.snapshot?.reschedules.count, countBefore + 1)
        let event = try XCTUnwrap(model.snapshot?.reschedules.last)
        XCTAssertEqual(event.reason, "等待接口联调")
        XCTAssertEqual(event.delayDays, 2)
        XCTAssertFalse(event.wasOverdueAtChange)
        XCTAssertEqual(model.phase, .loaded)
        let row = try XCTUnwrap(
            model.presentation?.gantt.rows.first { $0.id == task.id }
        )
        XCTAssertFalse(row.hasDelay)
        XCTAssertNil(row.delayLabel)
        XCTAssertEqual(row.rescheduleCount, 1)
    }

    func testFeatureModelUsesServerAuthoritativeViewerRole() async {
        let snapshot = KshiftPlanSampleData.makeSnapshot()
        let boundary = InMemoryKshiftPlanDepthBoundary(
            snapshot: snapshot,
            viewerRole: .viewer
        )
        let model = KshiftPlanDepthFeatureModel(
            boundary: boundary,
            capabilities: KshiftNoopPlatformCapabilities()
        )
        await model.load()
        XCTAssertEqual(model.viewerRole, .viewer)
    }
}
