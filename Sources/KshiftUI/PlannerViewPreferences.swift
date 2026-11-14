import Foundation

public struct PlannerViewPreferences: Codable, Equatable, Sendable {
    public var viewMode: PlannerViewMode
    public var selectedDate: String?
    public var schedulePeriod: SchedulePeriod
    public var scheduleDensity: ScheduleDensity
    public var schedulePeopleColumnWidth: CGFloat
    public var scheduleDateColumnWidth: CGFloat
    public var scheduleScrollAnchorDayID: String?
    public var collapsedSchedulePersonIDs: Set<String>

    public init(
        viewMode: PlannerViewMode = .peopleSchedule,
        selectedDate: String? = nil,
        schedulePeriod: SchedulePeriod = .week,
        scheduleDensity: ScheduleDensity = .compact,
        schedulePeopleColumnWidth: CGFloat = 196,
        scheduleDateColumnWidth: CGFloat = 96,
        scheduleScrollAnchorDayID: String? = nil,
        collapsedSchedulePersonIDs: Set<String> = []
    ) {
        self.viewMode = viewMode
        self.selectedDate = selectedDate
        self.schedulePeriod = schedulePeriod
        self.scheduleDensity = scheduleDensity
        self.schedulePeopleColumnWidth = schedulePeopleColumnWidth
        self.scheduleDateColumnWidth = scheduleDateColumnWidth
        self.scheduleScrollAnchorDayID = scheduleScrollAnchorDayID
        self.collapsedSchedulePersonIDs = collapsedSchedulePersonIDs
    }
}

public final class PlannerViewPreferencesStore {
    private let defaults: UserDefaults
    private let keyPrefix: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        defaults: UserDefaults = .standard,
        keyPrefix: String = "kshift.planner-view.v1"
    ) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    public func load(projectID: String) -> PlannerViewPreferences? {
        guard let data = defaults.data(forKey: key(projectID: projectID)) else {
            return nil
        }
        return try? decoder.decode(PlannerViewPreferences.self, from: data)
    }

    public func save(_ preferences: PlannerViewPreferences, projectID: String) {
        guard let data = try? encoder.encode(preferences) else { return }
        defaults.set(data, forKey: key(projectID: projectID))
    }

    public func remove(projectID: String) {
        defaults.removeObject(forKey: key(projectID: projectID))
    }

    private func key(projectID: String) -> String {
        "\(keyPrefix).\(projectID)"
    }
}
