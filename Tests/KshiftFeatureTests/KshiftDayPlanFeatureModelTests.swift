import Foundation
import KshiftFFI
import KshiftPresentation
import KshiftUI
import XCTest

@MainActor
final class KshiftDayPlanFeatureModelTests: XCTestCase {
  func testModelLoadsAndMutatesThroughTypedFFIBoundary() async {
    let setup = makeSetup()
    let capabilities = RecordingCapabilities()
    let model = makeModel(setup: setup, capabilities: capabilities)

    await model.load()

    XCTAssertEqual(model.phase, .loaded)
    XCTAssertEqual(model.presentation?.progressLabel, "1 / 4 已完成")

    guard let firstOpenTask = model.presentation?.tasks.first(where: { !$0.isCompleted }) else {
      return XCTFail("Missing open task")
    }
    await model.toggle(firstOpenTask)

    XCTAssertEqual(model.conflict, nil)
    XCTAssertEqual(model.presentation?.progressLabel, "2 / 4 已完成")
    XCTAssertEqual(capabilities.successCount, 1)
  }

  func testStaleRevisionShowsConflictWithoutOverwriting() async throws {
    let setup = makeSetup()
    let capabilities = RecordingCapabilities()
    let model = makeModel(setup: setup, capabilities: capabilities)
    await model.load()

    guard let firstOpenTask = model.presentation?.tasks.first(where: { !$0.isCompleted }) else {
      return XCTFail("Missing open task")
    }

    _ = try await setup.boundary.execute(
      .setTaskStatus(
        projectID: setup.snapshot.projectID,
        workDate: setup.snapshot.workDate,
        taskID: firstOpenTask.id,
        status: .inProgress,
        expectedRevision: setup.snapshot.revision
      )
    )

    await model.toggle(firstOpenTask)

    XCTAssertNotNil(model.conflict)
    XCTAssertEqual(model.presentation?.revisionLabel, "版本 7")
    XCTAssertEqual(model.presentation?.progressLabel, "1 / 4 已完成")
  }

  func testFilterChangesOnlyRebuildSharedPresentation() async {
    let setup = makeSetup()
    let model = makeModel(setup: setup, capabilities: RecordingCapabilities())
    await model.load()

    model.filter = .open

    XCTAssertEqual(model.presentation?.selectedFilter, .open)
    XCTAssertEqual(model.presentation?.tasks.count, 3)
  }

  private func makeSetup() -> Setup {
    let snapshot = KshiftSampleData.makeSnapshot(now: Date(timeIntervalSince1970: 1_800_000_000))
    let viewer = snapshot.members.first(where: { $0.id == snapshot.viewerID })!
    return Setup(
      snapshot: snapshot, viewer: viewer, boundary: InMemoryKshiftFFIBoundary(snapshot: snapshot))
  }

  private func makeModel(setup: Setup, capabilities: RecordingCapabilities)
    -> KshiftDayPlanFeatureModel
  {
    KshiftDayPlanFeatureModel(
      boundary: setup.boundary,
      capabilities: capabilities,
      projectID: setup.snapshot.projectID,
      workDate: setup.snapshot.workDate,
      viewer: setup.viewer,
      locale: Locale(identifier: "zh_Hans_CN"),
      timeZone: TimeZone(secondsFromGMT: 0)!
    )
  }

  private struct Setup {
    let snapshot: KshiftDayPlanSnapshot
    let viewer: KshiftUser
    let boundary: InMemoryKshiftFFIBoundary
  }
}

@MainActor
private final class RecordingCapabilities: KshiftPlatformCapabilities {
  let platform: KshiftPlatform = .macOS
  private(set) var successCount = 0

  func openExternalURL(_ url: URL) async -> Bool {
    true
  }

  func perform(_ feedback: KshiftPlatformFeedback) {
    if feedback == .success {
      successCount += 1
    }
  }
}
