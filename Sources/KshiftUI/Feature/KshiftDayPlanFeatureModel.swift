import Foundation
import KshiftFFI
import KshiftPresentation
import Observation

public enum KshiftDayPlanPhase: Equatable, Sendable {
  case idle
  case loading
  case loaded
  case failed(String)
}

@MainActor
@Observable
public final class KshiftDayPlanFeatureModel {
  public private(set) var phase: KshiftDayPlanPhase = .idle
  public private(set) var presentation: KshiftDayPlanPresentation?
  public private(set) var pendingTaskID: UUID?
  public private(set) var conflict: KshiftConflictPresentation?
  public var filter: KshiftDayPlanFilter = .all {
    didSet {
      rebuildPresentation()
    }
  }

  @ObservationIgnored private let boundary: any KshiftFFIBoundary
  @ObservationIgnored private let capabilities: any KshiftPlatformCapabilities
  @ObservationIgnored private let projectID: UUID
  @ObservationIgnored private let workDate: Date
  @ObservationIgnored private let viewer: KshiftUser
  @ObservationIgnored private let mapper: KshiftDayPlanPresentationMapper
  private var snapshot: KshiftDayPlanSnapshot?

  public init(
    boundary: any KshiftFFIBoundary,
    capabilities: any KshiftPlatformCapabilities,
    projectID: UUID,
    workDate: Date,
    viewer: KshiftUser,
    locale: Locale = .current,
    timeZone: TimeZone = .current
  ) {
    self.boundary = boundary
    self.capabilities = capabilities
    self.projectID = projectID
    self.workDate = workDate
    self.viewer = viewer
    self.mapper = KshiftDayPlanPresentationMapper(locale: locale, timeZone: timeZone)
  }

  public func loadIfNeeded() async {
    guard phase == .idle || isFailure else {
      return
    }
    await load()
  }

  public func load() async {
    phase = .loading
    conflict = nil
    do {
      let snapshot = try await boundary.fetchDayPlan(projectID: projectID, workDate: workDate)
      apply(snapshot)
      phase = .loaded
    } catch {
      phase = .failed(errorMessage(for: error))
    }
  }

  public func toggle(_ task: KshiftTaskItemPresentation) async {
    guard pendingTaskID == nil, let snapshot else {
      return
    }
    let nextStatus: KshiftTaskStatus = task.isCompleted ? .todo : .done
    pendingTaskID = task.id
    defer { pendingTaskID = nil }

    do {
      let updated = try await boundary.execute(
        .setTaskStatus(
          projectID: projectID,
          workDate: workDate,
          taskID: task.id,
          status: nextStatus,
          expectedRevision: snapshot.revision
        )
      )
      apply(updated)
      capabilities.perform(nextStatus == .done ? .success : .selection)
    } catch let error as KshiftFFIError {
      if case .conflict = error {
        conflict = mapper.conflictPresentation()
      } else {
        phase = .failed(errorMessage(for: error))
        capabilities.perform(.error)
      }
    } catch {
      phase = .failed(errorMessage(for: error))
      capabilities.perform(.error)
    }
  }

  public func dismissConflict() {
    conflict = nil
  }

  private var isFailure: Bool {
    if case .failed = phase {
      true
    } else {
      false
    }
  }

  private func apply(_ snapshot: KshiftDayPlanSnapshot) {
    self.snapshot = snapshot
    rebuildPresentation()
  }

  private func rebuildPresentation() {
    guard let snapshot else {
      presentation = nil
      return
    }
    presentation = mapper.makePresentation(
      snapshot: snapshot,
      filter: filter,
      viewerID: viewer.id
    )
  }

  private func errorMessage(for error: Error) -> String {
    guard let error = error as? KshiftFFIError else {
      return "无法读取日计划。请稍后重试。"
    }
    switch error {
    case .unavailable:
      return "共享服务不可用。请检查内网连接。"
    case .unauthorized:
      return "当前账号无权读取此项目。"
    case .notFound:
      return "找不到当前项目的日计划。"
    case .conflict(let currentRevision):
      return "任务已被其他成员更新到版本 \(currentRevision)。"
    case .invalidResponse, .invalidUTF8:
      return "共享服务返回了无法识别的数据。"
    case .cancelled:
      return "请求已取消。"
    case .released:
      return "客户端已释放。请重新打开页面。"
    }
  }
}
