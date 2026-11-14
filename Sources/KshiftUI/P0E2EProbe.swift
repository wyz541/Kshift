#if DEBUG
  import Foundation
  import KshiftCore
  import KshiftPresentation

  public struct KshiftP0E2EExpectations: Sendable {
    public let primaryProjectName: String
    public let secondaryProjectName: String
    public let primaryTimeZone: String
    public let secondaryTimeZone: String
    public let primaryDate: String
    public let secondaryDate: String
    public let actorID: String
    public let secondUserID: String
    public let searchTerm: String
    public let sharedTaskTitle: String

    public init(
      primaryProjectName: String,
      secondaryProjectName: String,
      primaryTimeZone: String,
      secondaryTimeZone: String,
      primaryDate: String,
      secondaryDate: String,
      actorID: String,
      secondUserID: String,
      searchTerm: String,
      sharedTaskTitle: String
    ) {
      self.primaryProjectName = primaryProjectName
      self.secondaryProjectName = secondaryProjectName
      self.primaryTimeZone = primaryTimeZone
      self.secondaryTimeZone = secondaryTimeZone
      self.primaryDate = primaryDate
      self.secondaryDate = secondaryDate
      self.actorID = actorID
      self.secondUserID = secondUserID
      self.searchTerm = searchTerm
      self.sharedTaskTitle = sharedTaskTitle
    }

    public static func fromEnvironment(
      _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> KshiftP0E2EExpectations? {
      guard let primaryProjectName = environment["KSHIFT_E2E_PRIMARY_PROJECT"],
            let secondaryProjectName = environment["KSHIFT_E2E_SECONDARY_PROJECT"],
            let primaryTimeZone = environment["KSHIFT_E2E_PRIMARY_TIME_ZONE"],
            let secondaryTimeZone = environment["KSHIFT_E2E_SECONDARY_TIME_ZONE"],
            let primaryDate = environment["KSHIFT_E2E_PRIMARY_DATE"],
            let secondaryDate = environment["KSHIFT_E2E_SECONDARY_DATE"],
            let actorID = environment["KSHIFT_ACTOR_ID"],
            let secondUserID = environment["KSHIFT_E2E_SECOND_USER_ID"],
            let searchTerm = environment["KSHIFT_E2E_SEARCH_TERM"],
            let sharedTaskTitle = environment["KSHIFT_E2E_SHARED_TASK"]
      else {
        return nil
      }
      return KshiftP0E2EExpectations(
        primaryProjectName: primaryProjectName,
        secondaryProjectName: secondaryProjectName,
        primaryTimeZone: primaryTimeZone,
        secondaryTimeZone: secondaryTimeZone,
        primaryDate: primaryDate,
        secondaryDate: secondaryDate,
        actorID: actorID,
        secondUserID: secondUserID,
        searchTerm: searchTerm,
        sharedTaskTitle: sharedTaskTitle
      )
    }
  }

  public struct KshiftP0E2EReport: Codable, Sendable {
    public let platform: String
    public let steps: [String]
    public let primaryRevision: UInt64
    public let secondaryRevision: UInt64
    public let primaryDate: String
    public let secondaryDate: String
  }

  public struct KshiftP0E2EFailure: Error, CustomStringConvertible, Sendable {
    public let step: String
    public let message: String

    public var description: String { "\(step): \(message)" }
  }

  @MainActor
  public enum KshiftP0E2EProbe {
    public static func run(
      model: AppModel,
      platform: KshiftPlatform,
      expectations: KshiftP0E2EExpectations
    ) async throws -> KshiftP0E2EReport {
      var steps: [String] = []

      func require(_ condition: @autoclosure () -> Bool, _ step: String, _ message: String) throws {
        guard condition() else {
          throw KshiftP0E2EFailure(step: step, message: message)
        }
        steps.append(step)
      }

      await model.bootstrap()
      try require(
        Set(model.projects.map(\.name)).isSuperset(of: [
          expectations.primaryProjectName,
          expectations.secondaryProjectName,
        ]),
        "projects",
        "Expected both live projects."
      )
      let primary = try project(named: expectations.primaryProjectName, in: model)
      let secondary = try project(named: expectations.secondaryProjectName, in: model)

      await model.selectProject(primary.id)
      try require(
        model.selectedDateString == expectations.primaryDate,
        "primary-time-zone",
        "Expected primary project date \(expectations.primaryDate), got \(model.selectedDateString)."
      )
      try require(
        model.projectTimeZone.identifier == expectations.primaryTimeZone,
        "primary-time-zone-id",
        "Expected \(expectations.primaryTimeZone)."
      )
      try require(
        model.selectedDateTasks.contains(where: { $0.title == expectations.sharedTaskTitle }),
        "primary-tasks",
        "Expected the shared fixture task."
      )
      try require(
        model.taskCount(on: model.selectedDate) >= 2,
        "calendar-count",
        "Expected daily calendar count from the project calendar."
      )

      for mode in PlannerViewMode.allCases {
        model.viewMode = mode
        try require(
          !model.selectedDateTasks.isEmpty,
          "view-\(mode.rawValue)",
          "View mode must preserve the project-date task set."
        )
      }
      model.viewMode = .board

      model.searchText = expectations.searchTerm
      try require(
        model.selectedDateTasks.contains(where: { $0.title == expectations.sharedTaskTitle }),
        "search",
        "Search must find the shared task."
      )
      model.searchText = ""

      model.filter.assigneeIDs = [expectations.secondUserID]
      try require(
        model.selectedDateTasks.allSatisfy { $0.assigneeIDs.contains(expectations.secondUserID) },
        "assignee-filter",
        "Assignee filter must match every selected assignee."
      )
      model.filter.statuses = [.todo]
      model.filter.priorities = [.high]
      try require(
        model.selectedDateTasks.contains(where: { $0.title == expectations.sharedTaskTitle }),
        "combined-filter",
        "Combined filters must keep the shared task."
      )
      model.filter.reset()

      model.sortOption = .priority
      try require(
        nondecreasing(model.selectedDateTasks.map(\.priority.sortOrder)),
        "sort-priority",
        "Priority sort order is invalid."
      )
      model.sortOption = .title
      let titles = model.selectedDateTasks.map(\.title)
      try require(
        titles == titles.sorted { $0.localizedStandardCompare($1) == .orderedAscending },
        "sort-title",
        "Title sort order is invalid."
      )
      model.sortOption = .manual

      let primaryDate = try requiredDate(expectations.primaryDate, calendar: model.projectCalendar)
      let suffix = UUID().uuidString.prefix(8)
      let createdTitle = "P0 \(platform.rawValue) task \(suffix)"
      let updatedTitle = "P0 \(platform.rawValue) updated \(suffix)"
      let createDraft = TaskDraft(
        projectID: primary.id,
        title: createdTitle,
        notes: "Live P0 create operation.",
        status: .todo,
        priority: .high,
        assigneeIDs: [expectations.actorID, expectations.secondUserID],
        dueDate: primaryDate,
        position: 8_192
      )
      let saved = await model.saveTask(createDraft)
      try require(saved, "create-task", "Create command failed.")
      guard let created = task(titled: createdTitle, in: model) else {
        throw KshiftP0E2EFailure(step: "create-task", message: "Created task is missing.")
      }
      try require(
        Set(created.assigneeIDs) == Set([expectations.actorID, expectations.secondUserID]),
        "multi-assignee-create",
        "Created task did not keep both assignees."
      )

      let updateDraft = TaskDraft(
        projectID: primary.id,
        taskID: created.id,
        expectedVersion: created.version,
        title: updatedTitle,
        notes: "Live P0 update operation.",
        status: .inProgress,
        priority: .urgent,
        assigneeIDs: [expectations.secondUserID],
        dueDate: primaryDate,
        position: created.position
      )
      let updated = await model.saveTask(updateDraft)
      try require(updated, "edit-task", "Update command failed.")
      guard let edited = task(titled: updatedTitle, in: model) else {
        throw KshiftP0E2EFailure(step: "edit-task", message: "Edited task is missing.")
      }
      try require(edited.status == .inProgress, "edit-status", "Status was not updated.")
      try require(edited.priority == .urgent, "edit-priority", "Priority was not updated.")
      try require(edited.assigneeIDs == [expectations.secondUserID], "edit-assignee", "Assignee was not replaced.")

      await model.moveTask(
        taskID: edited.id,
        assigneeIDs: [expectations.actorID],
        date: primaryDate,
        position: edited.position + 1_024
      )
      guard let moved = task(titled: updatedTitle, in: model) else {
        throw KshiftP0E2EFailure(step: "drag-task", message: "Moved task is missing.")
      }
      try require(moved.assigneeIDs == [expectations.actorID], "drag-assignee", "Drag did not replace the assignee.")
      try require(moved.dueDate == expectations.primaryDate, "drag-date", "Drag did not keep the project date.")
      try require(
        model.columns
          .first(where: { $0.id == expectations.actorID })?
          .tasks.contains(where: { $0.id == moved.id }) == true,
        "drag-column",
        "Dragged task is missing from the target assignee column."
      )

      await model.toggleDone(moved)
      guard let done = task(titled: updatedTitle, in: model) else {
        throw KshiftP0E2EFailure(step: "toggle-done", message: "Task missing after status toggle.")
      }
      try require(done.status == .done, "toggle-done", "Task was not marked done.")
      await model.toggleDone(done)
      guard let reopened = task(titled: updatedTitle, in: model) else {
        throw KshiftP0E2EFailure(step: "toggle-todo", message: "Task missing after reopen.")
      }
      try require(reopened.status == .todo, "toggle-todo", "Task was not reopened.")

      guard let shared = task(titled: expectations.sharedTaskTitle, in: model) else {
        throw KshiftP0E2EFailure(step: "batch-select", message: "Shared task is missing.")
      }
      model.toggleSelection(shared.id)
      model.toggleSelection(reopened.id)
      await model.setStatusForSelection(.blocked)
      try require(
        task(titled: expectations.sharedTaskTitle, in: model)?.status == .blocked,
        "batch-status-shared",
        "Batch status did not update the shared task."
      )
      try require(
        task(titled: updatedTitle, in: model)?.status == .blocked,
        "batch-status-created",
        "Batch status did not update the created task."
      )

      model.toggleSelection(shared.id)
      guard let blockedCreated = task(titled: updatedTitle, in: model) else {
        throw KshiftP0E2EFailure(step: "batch-reset", message: "Created task is missing.")
      }
      model.toggleSelection(blockedCreated.id)
      await model.setStatusForSelection(.todo)
      try require(
        task(titled: expectations.sharedTaskTitle, in: model)?.status == .todo,
        "batch-reset-shared",
        "Shared task was not reset."
      )
      try require(
        task(titled: updatedTitle, in: model)?.status == .todo,
        "batch-reset-created",
        "Created task was not reset."
      )

      await model.refresh()
      guard let withHistory = task(titled: updatedTitle, in: model) else {
        throw KshiftP0E2EFailure(step: "history", message: "Task missing after refresh.")
      }
      try require(!withHistory.history.isEmpty, "history", "Live task history is empty.")

      let revision = model.snapshot?.project.revision ?? 0
      let staleRevision = revision > 1 ? revision - 1 : 1
      let conflict = try await model.client.execute(
        projectID: primary.id,
        envelope: CommandEnvelope(
          expectedRevision: staleRevision,
          actorID: expectations.actorID,
          command: .update(
            UpdateTaskCommand(
              taskID: withHistory.id,
              expectedTaskVersion: withHistory.version,
              title: "Stale overwrite",
              notes: withHistory.notes,
              status: withHistory.status,
              priority: withHistory.priority,
              assigneeIDs: withHistory.assigneeIDs,
              dueDate: withHistory.dueDate,
              position: withHistory.position
            )
          )
        )
      )
      try require(!conflict.ok, "conflict", "Stale revision must fail.")
      try require(
        conflict.error?.code == "revision_conflict",
        "conflict-code",
        "Expected revision_conflict."
      )
      try require(
        task(titled: updatedTitle, in: model)?.title == updatedTitle,
        "conflict-no-overwrite",
        "Conflict overwrote the task."
      )

      let deleted = await model.deleteTask(withHistory)
      try require(
        deleted,
        "delete-task",
        "Delete command failed."
      )
      try require(task(titled: updatedTitle, in: model) == nil, "delete-verify", "Deleted task remains.")

      await model.selectProject(secondary.id)
      try require(
        model.selectedDateString == expectations.secondaryDate,
        "secondary-time-zone",
        "Expected secondary project date \(expectations.secondaryDate), got \(model.selectedDateString)."
      )
      try require(
        model.projectTimeZone.identifier == expectations.secondaryTimeZone,
        "secondary-time-zone-id",
        "Expected \(expectations.secondaryTimeZone)."
      )
      try require(
        !model.tasks.contains(where: { $0.projectID == primary.id }),
        "project-isolation",
        "Primary project tasks leaked into the secondary project."
      )
      let secondaryRevision = model.snapshot?.project.revision ?? 0

      await model.selectProject(primary.id)
      let primaryRevision = model.snapshot?.project.revision ?? 0
      return KshiftP0E2EReport(
        platform: platform.rawValue,
        steps: steps,
        primaryRevision: primaryRevision,
        secondaryRevision: secondaryRevision,
        primaryDate: expectations.primaryDate,
        secondaryDate: expectations.secondaryDate
      )
    }

    private static func project(named name: String, in model: AppModel) throws -> ProjectSummary {
      guard let project = model.projects.first(where: { $0.name == name }) else {
        throw KshiftP0E2EFailure(step: "projects", message: "Missing project \(name).")
      }
      return project
    }

    private static func task(titled title: String, in model: AppModel) -> TaskItem? {
      model.tasks.first(where: { $0.title == title })
    }

    private static func requiredDate(_ value: String, calendar: Calendar) throws -> Date {
      guard let date = KshiftDate.date(from: value, calendar: calendar) else {
        throw KshiftP0E2EFailure(step: "date", message: "Invalid date \(value).")
      }
      return date
    }

    private static func nondecreasing(_ values: [Int]) -> Bool {
      zip(values, values.dropFirst()).allSatisfy { pair in pair.0 <= pair.1 }
    }
  }
#endif
