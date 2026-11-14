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

        return AppModel(
            client: client,
            platform: platform,
            userTimeZone: userTimeZone,
            fallbackUserTimeZoneToProject: fallbackToProject,
            now: fixedNow.map { value in { value } } ?? Date.init
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
