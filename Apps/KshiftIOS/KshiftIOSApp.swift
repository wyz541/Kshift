#if os(iOS)
  import KshiftCore
  import KshiftUI
  import KshiftUIKitAdapter
  import SwiftUI

  @main
  struct KshiftIOSApp: App {
    @StateObject private var model = KshiftRuntimeEnvironment.makeModel(
      client: KshiftClientFactory.makeDefault(),
      platform: UIKitPlatformCapabilities()
    )

    var body: some Scene {
      WindowGroup {
        KshiftRootView(model: model)
          .environment(
            \.kshiftForceReduceTransparency,
            ProcessInfo.processInfo.environment["KSHIFT_FORCE_REDUCE_TRANSPARENCY"] == "1"
          )
          .tint(.accentColor)
          .background {
            UIKitSceneAccessor { _ in }
              .frame(width: 0, height: 0)
              .accessibilityHidden(true)
          }
      }
    }
  }
#endif
