import Foundation

public enum KshiftDayPlanFilter: String, CaseIterable, Identifiable, Sendable {
  case all
  case mine
  case open

  public var id: String { rawValue }
}

public enum KshiftSemanticRole: String, Sendable {
  case primary
  case secondary
  case accent
  case success
  case warning
  case danger
  case neutral
}

public struct KshiftDayPlanFilterPresentation: Identifiable, Hashable, Sendable {
  public let filter: KshiftDayPlanFilter
  public let title: String

  public var id: KshiftDayPlanFilter { filter }

  public init(filter: KshiftDayPlanFilter, title: String) {
    self.filter = filter
    self.title = title
  }
}

public struct KshiftTaskItemPresentation: Identifiable, Hashable, Sendable {
  public let id: UUID
  public let title: String
  public let details: String?
  public let statusLabel: String
  public let priorityLabel: String
  public let assigneeLabel: String
  public let statusRole: KshiftSemanticRole
  public let priorityRole: KshiftSemanticRole
  public let isCompleted: Bool
  public let accessibilityLabel: String
  public let accessibilityHint: String

  public init(
    id: UUID,
    title: String,
    details: String?,
    statusLabel: String,
    priorityLabel: String,
    assigneeLabel: String,
    statusRole: KshiftSemanticRole,
    priorityRole: KshiftSemanticRole,
    isCompleted: Bool,
    accessibilityLabel: String,
    accessibilityHint: String
  ) {
    self.id = id
    self.title = title
    self.details = details
    self.statusLabel = statusLabel
    self.priorityLabel = priorityLabel
    self.assigneeLabel = assigneeLabel
    self.statusRole = statusRole
    self.priorityRole = priorityRole
    self.isCompleted = isCompleted
    self.accessibilityLabel = accessibilityLabel
    self.accessibilityHint = accessibilityHint
  }
}

public struct KshiftDayPlanPresentation: Hashable, Sendable {
  public let projectTitle: String
  public let dateLabel: String
  public let revisionLabel: String
  public let progressLabel: String
  public let progressFraction: Double
  public let filters: [KshiftDayPlanFilterPresentation]
  public let selectedFilter: KshiftDayPlanFilter
  public let tasks: [KshiftTaskItemPresentation]
  public let hiddenTaskCount: Int
  public let emptyTitle: String
  public let emptyMessage: String
  public let accessibilitySummary: String

  public init(
    projectTitle: String,
    dateLabel: String,
    revisionLabel: String,
    progressLabel: String,
    progressFraction: Double,
    filters: [KshiftDayPlanFilterPresentation],
    selectedFilter: KshiftDayPlanFilter,
    tasks: [KshiftTaskItemPresentation],
    hiddenTaskCount: Int,
    emptyTitle: String,
    emptyMessage: String,
    accessibilitySummary: String
  ) {
    self.projectTitle = projectTitle
    self.dateLabel = dateLabel
    self.revisionLabel = revisionLabel
    self.progressLabel = progressLabel
    self.progressFraction = progressFraction
    self.filters = filters
    self.selectedFilter = selectedFilter
    self.tasks = tasks
    self.hiddenTaskCount = hiddenTaskCount
    self.emptyTitle = emptyTitle
    self.emptyMessage = emptyMessage
    self.accessibilitySummary = accessibilitySummary
  }
}

public struct KshiftConflictPresentation: Equatable, Sendable {
  public let title: String
  public let message: String
  public let refreshTitle: String

  public init(title: String, message: String, refreshTitle: String) {
    self.title = title
    self.message = message
    self.refreshTitle = refreshTitle
  }
}
