import Foundation
import KshiftPresentation

public actor InMemoryKshiftFFIBoundary: KshiftFFIBoundary {
  private var snapshot: KshiftDayPlanSnapshot

  public init(snapshot: KshiftDayPlanSnapshot) {
    self.snapshot = snapshot
  }

  public func fetchDayPlan(projectID: UUID, workDate: Date) async throws -> KshiftDayPlanSnapshot {
    guard snapshot.projectID == projectID else {
      throw KshiftFFIError.notFound
    }
    guard Calendar(identifier: .gregorian).isDate(snapshot.workDate, inSameDayAs: workDate) else {
      throw KshiftFFIError.notFound
    }
    return snapshot
  }

  public func execute(_ command: KshiftDayPlanCommand) async throws -> KshiftDayPlanSnapshot {
    switch command {
    case .setTaskStatus(let projectID, let workDate, let taskID, let status, let expectedRevision):
      guard snapshot.projectID == projectID else {
        throw KshiftFFIError.notFound
      }
      guard Calendar(identifier: .gregorian).isDate(snapshot.workDate, inSameDayAs: workDate) else {
        throw KshiftFFIError.notFound
      }
      guard expectedRevision == snapshot.revision else {
        throw KshiftFFIError.conflict(currentRevision: snapshot.revision)
      }
      guard let index = snapshot.tasks.firstIndex(where: { $0.id == taskID }) else {
        throw KshiftFFIError.notFound
      }

      let nextRevision = snapshot.revision + 1
      let current = snapshot.tasks[index]
      let updated = KshiftTaskSnapshot(
        id: current.id,
        title: current.title,
        details: current.details,
        status: status,
        priority: current.priority,
        assigneeIDs: current.assigneeIDs,
        dueDate: current.dueDate,
        revision: nextRevision
      )
      var tasks = snapshot.tasks
      tasks[index] = updated
      snapshot = KshiftDayPlanSnapshot(
        projectID: snapshot.projectID,
        projectName: snapshot.projectName,
        projectTimeZoneIdentifier: snapshot.projectTimeZoneIdentifier,
        workDate: snapshot.workDate,
        revision: nextRevision,
        viewerID: snapshot.viewerID,
        members: snapshot.members,
        tasks: tasks
      )
      return snapshot
    }
  }
}

public enum KshiftSampleData {
  public static let projectID = UUID(uuidString: "9A1B9E80-1E2B-4B33-A28A-001122334455")!
  public static let viewerID = UUID(uuidString: "A1B2C3D4-0001-4000-8000-000000000001")!
  public static let memberIDs = [
    UUID(uuidString: "A1B2C3D4-0001-4000-8000-000000000002")!,
    UUID(uuidString: "A1B2C3D4-0001-4000-8000-000000000003")!,
  ]

  public static func makeSnapshot(now: Date = .now) -> KshiftDayPlanSnapshot {
    let members = [
      KshiftUser(id: viewerID, name: "林澈"),
      KshiftUser(id: memberIDs[0], name: "周宁"),
      KshiftUser(id: memberIDs[1], name: "陈默"),
    ]
    let tasks = [
      KshiftTaskSnapshot(
        id: UUID(uuidString: "B0000000-0000-4000-8000-000000000001")!,
        title: "完成共享页面骨架",
        details: "macOS 和 iOS 使用同一份 SwiftUI 页面。",
        status: .inProgress,
        priority: .high,
        assigneeIDs: [viewerID, memberIDs[0]],
        dueDate: now,
        revision: 1
      ),
      KshiftTaskSnapshot(
        id: UUID(uuidString: "B0000000-0000-4000-8000-000000000002")!,
        title: "补齐 adapter 边界测试",
        status: .todo,
        priority: .high,
        assigneeIDs: [memberIDs[0]],
        dueDate: now,
        revision: 1
      ),
      KshiftTaskSnapshot(
        id: UUID(uuidString: "B0000000-0000-4000-8000-000000000003")!,
        title: "核对 Liquid Glass 验收项",
        status: .todo,
        priority: .medium,
        assigneeIDs: [memberIDs[1]],
        dueDate: now,
        revision: 1
      ),
      KshiftTaskSnapshot(
        id: UUID(uuidString: "B0000000-0000-4000-8000-000000000004")!,
        title: "确认最小启动入口",
        status: .done,
        priority: .low,
        assigneeIDs: [viewerID],
        dueDate: now,
        revision: 1
      ),
    ]
    return KshiftDayPlanSnapshot(
      projectID: projectID,
      projectName: "Kshift 基座",
      projectTimeZoneIdentifier: "Asia/Shanghai",
      workDate: now,
      revision: 7,
      viewerID: viewerID,
      members: members,
      tasks: tasks
    )
  }

  public static func makeBoundary(now: Date = .now) -> InMemoryKshiftFFIBoundary {
    InMemoryKshiftFFIBoundary(snapshot: makeSnapshot(now: now))
  }
}
