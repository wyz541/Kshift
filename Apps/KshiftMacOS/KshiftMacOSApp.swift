#if os(macOS)
  import KshiftAppKitAdapter
  import KshiftUI
  import SwiftUI

  @main
  struct KshiftMacOSApp: App {
    var body: some Scene {
      WindowGroup {
        KshiftMacOSRoot()
          .frame(minWidth: 760, minHeight: 560)
      }
      .defaultSize(width: 1_040, height: 760)
    }
  }

  private struct KshiftMacOSRoot: View {
    private let capabilities = AppKitPlatformCapabilities()

    var body: some View {
      KshiftDayPlanFeatureView(capabilities: capabilities)
        .tint(.accentColor)
        .background {
          AppKitWindowAccessor { window in
            window?.isMovableByWindowBackground = true
          }
          .frame(width: 0, height: 0)
          .accessibilityHidden(true)
        }
    }
  }
#endif
