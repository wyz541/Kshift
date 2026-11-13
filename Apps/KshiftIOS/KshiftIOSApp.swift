#if os(iOS)
  import KshiftCore
  import KshiftUI
  import KshiftUIKitAdapter
  import SwiftUI

  @main
  struct KshiftIOSApp: App {
    @StateObject private var model = AppModel(
      client: RustClient(),
      platform: UIKitPlatformCapabilities()
    )

    var body: some Scene {
      WindowGroup {
        KshiftRootView(model: model)
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
