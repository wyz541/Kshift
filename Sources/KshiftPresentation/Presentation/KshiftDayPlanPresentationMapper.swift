import Foundation

public struct KshiftDayPlanPresentationMapper: Sendable {
  public static let maximumVisibleInteractiveCards = 6

  private let locale: Locale
  private let timeZone: TimeZone

  public init(locale: Locale = .current, timeZone: TimeZone = .current) {
    self.locale = locale
    self.timeZone = timeZone
  }

  public func makePresentation(
    snapshot: KshiftDayPlanSnapshot,
    filter: KshiftDayPlanFilter,
    viewerID: UUID
  ) -> KshiftDayPlanPresentation {
    let completedCount = snapshot.tasks.filter { $0.status == .done }.count
    let fraction =
      snapshot.tasks.isEmpty
      ? 0
      : Double(completedCount) / Double(snapshot.tasks.count)

    let matchingTasks = snapshot.tasks
      .filter { matches($0, filter: filter, viewerID: viewerID) }
      .sorted(by: taskSort)
    let visibleTasks = Array(matchingTasks.prefix(Self.maximumVisibleInteractiveCards))
    let hiddenCount = max(0, matchingTasks.count - visibleTasks.count)

    let taskPresentations = visibleTasks.map { task in
      let assigneeNames = task.assigneeIDs.compactMap { id in
        snapshot.members.first(where: { $0.id == id })?.name
      }
      let assignee = assigneeNames.isEmpty ? "未分配" : assigneeNames.joined(separator: "、")
      let status = statusLabel(task.status)
      let priority = priorityLabel(task.priority)
      let nextAction = task.status == .done ? "重新打开" : "完成任务"
      return KshiftTaskItemPresentation(
        id: task.id,
        title: task.title,
        details: task.details,
        statusLabel: status,
        priorityLabel: priority,
        assigneeLabel: assignee,
        statusRole: statusRole(task.status),
        priorityRole: priorityRole(task.priority),
        isCompleted: task.status == .done,
        accessibilityLabel: "\(task.title)，\(status)，优先级\(priority)，负责人\(assignee)",
        accessibilityHint: "\(nextAction)，预期版本 \(snapshot.revision)"
      )
    }

    let dateFormatter = DateFormatter()
    dateFormatter.locale = locale
    dateFormatter.timeZone = TimeZone(identifier: snapshot.projectTimeZoneIdentifier) ?? timeZone
    dateFormatter.calendar = Calendar(identifier: .gregorian)
    dateFormatter.dateFormat = "yyyy-MM-dd"

    let empty: (String, String)
    switch filter {
    case .all:
      empty = ("今天没有任务", "添加任务后，任务会出现在这里。")
    case .mine:
      empty = ("没有分配给你的任务", "切换筛选条件查看其他任务。")
    case .open:
      empty = ("没有未完成任务", "今天的任务已经全部完成。")
    }

    return KshiftDayPlanPresentation(
      projectTitle: "\(snapshot.projectName) · 日计划",
      dateLabel: dateFormatter.string(from: snapshot.workDate),
      revisionLabel: "版本 \(snapshot.revision)",
      progressLabel: "\(completedCount) / \(snapshot.tasks.count) 已完成",
      progressFraction: fraction,
      filters: [
        KshiftDayPlanFilterPresentation(filter: .all, title: "全部"),
        KshiftDayPlanFilterPresentation(filter: .mine, title: "我的"),
        KshiftDayPlanFilterPresentation(filter: .open, title: "未完成"),
      ],
      selectedFilter: filter,
      tasks: taskPresentations,
      hiddenTaskCount: hiddenCount,
      emptyTitle: empty.0,
      emptyMessage: empty.1,
      accessibilitySummary:
        "\(snapshot.projectName)，\(completedCount) 项已完成，共 \(snapshot.tasks.count) 项。当前筛选显示 \(matchingTasks.count) 项。"
    )
  }

  public func conflictPresentation() -> KshiftConflictPresentation {
    KshiftConflictPresentation(
      title: "任务已被其他成员更新",
      message: "Kshift 未覆盖新版本。请刷新后重新操作。",
      refreshTitle: "刷新任务"
    )
  }

  private func matches(_ task: KshiftTaskSnapshot, filter: KshiftDayPlanFilter, viewerID: UUID)
    -> Bool
  {
    switch filter {
    case .all:
      true
    case .mine:
      task.assigneeIDs.contains(viewerID)
    case .open:
      task.status != .done
    }
  }

  private func taskSort(_ left: KshiftTaskSnapshot, _ right: KshiftTaskSnapshot) -> Bool {
    if left.status != right.status {
      return statusOrder(left.status) < statusOrder(right.status)
    }
    if left.priority != right.priority {
      return priorityOrder(left.priority) < priorityOrder(right.priority)
    }
    return left.title.localizedStandardCompare(right.title) == .orderedAscending
  }

  private func statusOrder(_ status: KshiftTaskStatus) -> Int {
    switch status {
    case .inProgress: 0
    case .todo: 1
    case .done: 2
    }
  }

  private func priorityOrder(_ priority: KshiftPriority) -> Int {
    switch priority {
    case .high: 0
    case .medium: 1
    case .low: 2
    }
  }

  private func statusLabel(_ status: KshiftTaskStatus) -> String {
    switch status {
    case .todo: "待处理"
    case .inProgress: "进行中"
    case .done: "已完成"
    }
  }

  private func priorityLabel(_ priority: KshiftPriority) -> String {
    switch priority {
    case .high: "高"
    case .medium: "中"
    case .low: "低"
    }
  }

  private func statusRole(_ status: KshiftTaskStatus) -> KshiftSemanticRole {
    switch status {
    case .todo: .neutral
    case .inProgress: .accent
    case .done: .success
    }
  }

  private func priorityRole(_ priority: KshiftPriority) -> KshiftSemanticRole {
    switch priority {
    case .high: .danger
    case .medium: .warning
    case .low: .secondary
    }
  }
}
