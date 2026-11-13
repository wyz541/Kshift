import Foundation
import KshiftPresentation
import XCTest

final class KshiftDayPlanPresentationMapperTests: XCTestCase {
  func testFilteringUsesOneSharedPresentationMapping() {
    let snapshot = makeSnapshot()
    let mapper = KshiftDayPlanPresentationMapper(
      locale: Locale(identifier: "en_US_POSIX"),
      timeZone: TimeZone(secondsFromGMT: 0)!
    )

    let all = mapper.makePresentation(snapshot: snapshot, filter: .all, viewerID: snapshot.viewerID)
    let mine = mapper.makePresentation(
      snapshot: snapshot, filter: .mine, viewerID: snapshot.viewerID)
    let open = mapper.makePresentation(
      snapshot: snapshot, filter: .open, viewerID: snapshot.viewerID)

    XCTAssertEqual(all.tasks.count, 3)
    XCTAssertEqual(mine.tasks.count, 2)
    XCTAssertEqual(open.tasks.count, 2)
    XCTAssertEqual(all.progressLabel, "1 / 3 已完成")
    XCTAssertEqual(all.progressFraction, 1.0 / 3.0, accuracy: 0.0001)
  }

  func testSemanticRolesComeFromTypedSnapshot() {
    let snapshot = makeSnapshot()
    let mapper = KshiftDayPlanPresentationMapper()
    let presentation = mapper.makePresentation(
      snapshot: snapshot, filter: .all, viewerID: snapshot.viewerID)

    let highPriority = presentation.tasks.first(where: { $0.title == "高优先级任务" })
    let finished = presentation.tasks.first(where: { $0.title == "已完成任务" })

    XCTAssertEqual(highPriority?.priorityRole, .danger)
    XCTAssertEqual(highPriority?.statusRole, .accent)
    XCTAssertEqual(finished?.statusRole, .success)
    XCTAssertEqual(finished?.isCompleted, true)
  }

  func testInteractiveGlassCardCountIsBounded() {
    var snapshot = makeSnapshot()
    let extraTasks = (1...7).map { index in
      KshiftTaskSnapshot(
        id: UUID(),
        title: "额外任务 \(index)",
        status: .todo,
        priority: .medium,
        assigneeID: snapshot.viewerID,
        revision: 1
      )
    }
    snapshot = KshiftDayPlanSnapshot(
      projectID: snapshot.projectID,
      projectName: snapshot.projectName,
      workDate: snapshot.workDate,
      revision: snapshot.revision,
      viewerID: snapshot.viewerID,
      members: snapshot.members,
      tasks: snapshot.tasks + extraTasks
    )

    let mapper = KshiftDayPlanPresentationMapper()
    let presentation = mapper.makePresentation(
      snapshot: snapshot, filter: .all, viewerID: snapshot.viewerID)

    XCTAssertEqual(
      presentation.tasks.count, KshiftDayPlanPresentationMapper.maximumVisibleInteractiveCards)
    XCTAssertEqual(
      presentation.hiddenTaskCount,
      snapshot.tasks.count - KshiftDayPlanPresentationMapper.maximumVisibleInteractiveCards
    )
  }

  private func makeSnapshot() -> KshiftDayPlanSnapshot {
    let viewerID = UUID()
    let otherID = UUID()
    let members = [
      KshiftUser(id: viewerID, name: "当前用户"),
      KshiftUser(id: otherID, name: "其他成员"),
    ]
    return KshiftDayPlanSnapshot(
      projectID: UUID(),
      projectName: "示例项目",
      workDate: Date(timeIntervalSince1970: 1_800_000_000),
      revision: 5,
      viewerID: viewerID,
      members: members,
      tasks: [
        KshiftTaskSnapshot(
          id: UUID(),
          title: "高优先级任务",
          status: .inProgress,
          priority: .high,
          assigneeID: viewerID,
          revision: 5
        ),
        KshiftTaskSnapshot(
          id: UUID(),
          title: "他人任务",
          status: .todo,
          priority: .medium,
          assigneeID: otherID,
          revision: 5
        ),
        KshiftTaskSnapshot(
          id: UUID(),
          title: "已完成任务",
          status: .done,
          priority: .low,
          assigneeID: viewerID,
          revision: 5
        ),
      ]
    )
  }
}
