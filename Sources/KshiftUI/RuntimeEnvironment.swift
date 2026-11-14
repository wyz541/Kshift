import Foundation
import KshiftCore
import KshiftPresentation

@MainActor
public enum KshiftRuntimeEnvironment {
    public static func makeModel(
        client: any KshiftClientProtocol,
        platform: any KshiftPlatformCapabilities,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppModel {
        let configuredTimeZone = environment["KSHIFT_USER_TIME_ZONE"]
        let userTimeZone = configuredTimeZone.flatMap(TimeZone.init(identifier:))
        let fallbackToProject = configuredTimeZone != nil && userTimeZone == nil
        let fixedNow = environment["KSHIFT_NOW"].flatMap(parseTimestamp)
        let initialViewMode = environment["KSHIFT_INITIAL_VIEW_MODE"].flatMap(PlannerViewMode.init(rawValue:))
        let preferencesStore: PlannerViewPreferencesStore
        if environment["KSHIFT_RESET_PLANNER_VIEW_STATE"] == "1",
           let defaults = UserDefaults(suiteName: "kshift.ui-test.\(UUID().uuidString)")
        {
            preferencesStore = PlannerViewPreferencesStore(defaults: defaults)
        } else {
            preferencesStore = PlannerViewPreferencesStore()
        }

        return AppModel(
            client: client,
            platform: platform,
            userTimeZone: userTimeZone,
            fallbackUserTimeZoneToProject: fallbackToProject,
            now: fixedNow.map { value in { value } } ?? Date.init,
            initialViewMode: initialViewMode,
            preferencesStore: preferencesStore
        )
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
