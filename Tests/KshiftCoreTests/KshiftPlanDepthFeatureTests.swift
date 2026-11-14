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
            .setTaskStatus(
                taskID: task.id,
                status: task.status == .done ? .todo : .done,
                expectedTaskVersion: task.version,
                expectedRevision: model.snapshot!.revision
            )
        )
        do {
            _ = try await boundary.execute(
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
}
