#if DEBUG && os(iOS)
  import Foundation
  import KshiftCore
  import KshiftPresentation
  import KshiftUIKitAdapter
  import KshiftUI

  @MainActor
  enum KshiftIOSLiveP0Harness {
    static var isConfigured: Bool {
      let environment = ProcessInfo.processInfo.environment
      return environment["KSHIFT_ENDPOINT"] != nil
        && environment["KSHIFT_TOKEN"] != nil
        && environment["KSHIFT_ACTOR_ID"] != nil
        && environment["KSHIFT_E2E_PRIMARY_PROJECT"] != nil
        && environment["KSHIFT_E2E_SECONDARY_PROJECT"] != nil
        && environment["KSHIFT_E2E_PRIMARY_TIME_ZONE"] != nil
        && environment["KSHIFT_E2E_SECONDARY_TIME_ZONE"] != nil
        && environment["KSHIFT_E2E_PRIMARY_DATE"] != nil
        && environment["KSHIFT_E2E_SECONDARY_DATE"] != nil
        && environment["KSHIFT_E2E_SECOND_USER_ID"] != nil
        && environment["KSHIFT_E2E_SEARCH_TERM"] != nil
        && environment["KSHIFT_E2E_SHARED_TASK"] != nil
        && (environment["KSHIFT_CA_PATH"] != nil || environment["KSHIFT_CA_PEM"] != nil)
    }

    static func run() async throws -> KshiftIOSLiveP0Summary {
      let environment = ProcessInfo.processInfo.environment
      guard let endpoint = environment["KSHIFT_ENDPOINT"],
            let token = environment["KSHIFT_TOKEN"],
            let actorID = environment["KSHIFT_ACTOR_ID"],
            let expectations = KshiftP0E2EExpectations.fromEnvironment(environment),
            let caPEM = caPEM(from: environment)
      else {
        throw KshiftIOSLiveP0HarnessError.notConfigured
      }

      let client = RustClient(
        actorID: actorID,
        endpoint: endpoint,
        caPEM: caPEM,
        token: token,
        deadlineMilliseconds: 15_000
      )
      let userTimeZone = TimeZone(
        identifier: environment["KSHIFT_USER_TIME_ZONE"] ?? ""
      ) ?? TimeZone(identifier: "America/Los_Angeles")!
      let now = parseTimestamp(environment["KSHIFT_NOW"]) ?? Date()
      let model = AppModel(
        client: client,
        platform: UIKitPlatformCapabilities(),
        userTimeZone: userTimeZone,
        now: { now }
      )
      let report = try await KshiftP0E2EProbe.run(
        model: model,
        platform: .iOS,
        expectations: expectations
      )
      return KshiftIOSLiveP0Summary(
        platform: report.platform,
        primaryDate: report.primaryDate,
        secondaryDate: report.secondaryDate,
        stepCount: report.steps.count
      )
    }

    private static func caPEM(from environment: [String: String]) -> Data? {
      if let value = environment["KSHIFT_CA_PEM"], !value.isEmpty {
        return Data(value.utf8)
      }
      guard let path = environment["KSHIFT_CA_PATH"], !path.isEmpty else {
        return nil
      }
      return try? Data(contentsOf: URL(fileURLWithPath: path))
    }

    private static func parseTimestamp(_ value: String?) -> Date? {
      guard let value else { return nil }
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = formatter.date(from: value) {
        return date
      }
      formatter.formatOptions = [.withInternetDateTime]
      return formatter.date(from: value)
    }
  }

  struct KshiftIOSLiveP0Summary: Sendable {
    let platform: String
    let primaryDate: String
    let secondaryDate: String
    let stepCount: Int
  }

  enum KshiftIOSLiveP0HarnessError: Error {
    case notConfigured
  }
#endif
