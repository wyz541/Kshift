import KshiftCore
import KshiftPlatform
import KshiftUI
import SwiftUI

@main
struct KshiftIOSApp: App {
    @StateObject private var model = AppModel(
        client: RustClient(),
        platform: IOSPlatformServices()
    )

    var body: some Scene {
        WindowGroup {
            KshiftRootView(model: model)
        }
    }
}
