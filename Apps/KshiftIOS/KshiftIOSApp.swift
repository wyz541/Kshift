#if os(iOS)
  import KshiftUI
  import KshiftUIKitAdapter
  import SwiftUI

  @main
  struct KshiftIOSApp: App {
    var body: some Scene {
      WindowGroup {
        KshiftIOSRoot()
      }
    }
  }

  private struct KshiftIOSRoot: View {
    private let capabilities = UIKitPlatformCapabilities()

    var body: some View {
      KshiftPlanDepthFeatureView(capabilities: capabilities)
        .tint(Color.kshift(.accent))
        .background {
          UIKitSceneAccessor { _ in }
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
    }
  }
#endif
