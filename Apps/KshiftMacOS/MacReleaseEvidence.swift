import AppKit
import Darwin
import KshiftAppKitAdapter
import KshiftCore
import KshiftUI
import SwiftUI

struct KshiftEvidenceEnvironmentModifier: ViewModifier {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  let environment: [String: String]

  func body(content: Content) -> some View {
    content
      .environment(\.colorScheme, forcedColorScheme ?? colorScheme)
      .environment(\.dynamicTypeSize, forcedDynamicTypeSize ?? dynamicTypeSize)
  }

  private var forcedColorScheme: ColorScheme? {
    switch environment["KSHIFT_FORCE_COLOR_SCHEME"] {
    case "light": .light
    case "dark": .dark
    default: nil
    }
  }

  private var forcedDynamicTypeSize: DynamicTypeSize? {
    switch environment["KSHIFT_FORCE_DYNAMIC_TYPE"] {
    case "large": .large
    case "accessibility1": .accessibility1
    case "accessibility2": .accessibility2
    case "accessibility3": .accessibility3
    case "accessibility4": .accessibility4
    case "accessibility5": .accessibility5
    default: nil
    }
  }

}

struct MacReleaseEvidenceCoordinator: View {
  @ObservedObject var model: AppModel
  let launchUptime: TimeInterval
  let screenshotPath: String?
  let metricsPath: String?
  @State private var window: NSWindow?

  var body: some View {
    Color.clear
      .frame(width: 0, height: 0)
      .background {
        AppKitWindowAccessor { window = $0 }
      }
      .task {
        for _ in 0..<300 {
          if model.hasLoaded, window != nil {
            try? await Task.sleep(for: .milliseconds(750))
            runEvidence()
            return
          }
          try? await Task.sleep(for: .milliseconds(100))
        }
        writeFailure("model or window did not become ready")
        NSApplication.shared.terminate(nil)
      }
  }

  private func runEvidence() {
    guard let window else {
      writeFailure("window is unavailable")
      NSApplication.shared.terminate(nil)
      return
    }
    NSApplication.shared.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    window.displayIfNeeded()

    var screenshotBytes = 0
    var screenshotError: String?
    if let screenshotPath, !screenshotPath.isEmpty {
      do {
        guard let data = windowImage(window)?.representation(using: .png, properties: [:]) else {
          throw EvidenceError.message("window image capture failed")
        }
        try data.write(to: URL(fileURLWithPath: screenshotPath), options: .atomic)
        screenshotBytes = data.count
      } catch {
        screenshotError = String(describing: error)
      }
    }

    let elapsed = (ProcessInfo.processInfo.systemUptime - launchUptime) * 1_000
    let metrics: [String: Any] = [
      "launch_to_evidence_ready_ms": elapsed,
      "model_loaded": model.hasLoaded,
      "screenshot_bytes": screenshotBytes,
      "screenshot_error": screenshotError as Any,
    ]
    if let metricsPath, !metricsPath.isEmpty {
      do {
        try writeJSON(metrics, to: metricsPath)
      } catch {
        writeFailure("metrics write failed: \(error)")
      }
    }

    if screenshotError == nil {
      print("KSHIFT_RELEASE_EVIDENCE_READY")
    }
    NSApplication.shared.terminate(nil)
  }

  private func writeFailure(_ message: String) {
    if let metricsPath, !metricsPath.isEmpty {
      try? writeJSON([
        "launch_to_evidence_ready_ms": (ProcessInfo.processInfo.systemUptime - launchUptime) * 1_000,
        "model_loaded": model.hasLoaded,
        "failure": message,
      ], to: metricsPath)
    }
    fputs("KSHIFT_RELEASE_EVIDENCE_FAILED \(message)\n", stderr)
  }

  private func writeJSON(_ value: [String: Any], to path: String) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .prettyPrinted])
    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
  }

  private func windowImage(_ window: NSWindow) -> NSBitmapImageRep? {
    typealias WindowImageFunction = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    guard let handle = dlopen(
      "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
      RTLD_LAZY
    ), let symbol = dlsym(handle, "CGWindowListCreateImage") else {
      return nil
    }
    defer { dlclose(handle) }
    let createImage = unsafeBitCast(symbol, to: WindowImageFunction.self)
    guard let image = createImage(
      .null,
      8,
      UInt32(window.windowNumber),
      9
    )?.takeRetainedValue() else {
      return nil
    }
    return NSBitmapImageRep(cgImage: image)
  }


}

private enum EvidenceError: Error {
  case message(String)
}
