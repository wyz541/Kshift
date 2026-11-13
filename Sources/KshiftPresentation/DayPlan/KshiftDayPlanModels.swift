import Foundation

public struct KshiftUser: Identifiable, Hashable, Sendable {
  public let id: UUID
  public let name: String

  public init(id: UUID, name: String) {
    self.id = id
    self.name = name
  }
}

public enum KshiftTaskStatus: String, CaseIterable, Codable, Sendable {
  case todo
  case inProgress = "in_progress"
  case done
}

public enum KshiftPriority: String, CaseIterable, Codable, Sendable {
  case high
  case medium
  case low
}

public struct KshiftTaskSnapshot: Identifiable, Hashable, Sendable {
  public let id: UUID
  public let title: String
  public let details: String?
  public let status: KshiftTaskStatus
  public let priority: KshiftPriority
  public let assigneeIDs: [UUID]
  public let dueDate: Date?
  public let revision: UInt64

  public init(
    id: UUID,
    title: String,
    details: String? = nil,
    status: KshiftTaskStatus,
    priority: KshiftPriority,
    assigneeIDs: [UUID] = [],
    dueDate: Date? = nil,
    revision: UInt64
  ) {
    self.id = id
    self.title = title
    self.details = details
    self.status = status
    self.priority = priority
    self.assigneeIDs = assigneeIDs
    self.dueDate = dueDate
    self.revision = revision
  }
}

public struct KshiftDayPlanSnapshot: Hashable, Sendable {
  public let projectID: UUID
  public let projectName: String
  public let projectTimeZoneIdentifier: String
  public let workDate: Date
  public let revision: UInt64
  public let viewerID: UUID
  public let members: [KshiftUser]
  public let tasks: [KshiftTaskSnapshot]

  public init(
    projectID: UUID,
    projectName: String,
    projectTimeZoneIdentifier: String = TimeZone.current.identifier,
    workDate: Date,
    revision: UInt64,
    viewerID: UUID,
    members: [KshiftUser],
    tasks: [KshiftTaskSnapshot]
  ) {
    self.projectID = projectID
    self.projectName = projectName
    self.projectTimeZoneIdentifier = projectTimeZoneIdentifier
    self.workDate = workDate
    self.revision = revision
    self.viewerID = viewerID
    self.members = members
    self.tasks = tasks
  }
}

public enum KshiftDayPlanCommand: Equatable, Sendable {
  case setTaskStatus(
    projectID: UUID,
    workDate: Date,
    taskID: UUID,
    status: KshiftTaskStatus,
    expectedRevision: UInt64
  )
}
