import AppKit
import ApplicationServices
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
  let auditPath: String?
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
            await runEvidence()
            return
          }
          try? await Task.sleep(for: .milliseconds(100))
        }
        writeFailure("model or window did not become ready")
        NSApplication.shared.terminate(nil)
      }
  }

  private func runEvidence() async {
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

    var audit: [String: Any]?
    if let auditPath, !auditPath.isEmpty {
      audit = await Self.auditApplicationAccessibility(pid: getpid())
      do {
        try writeJSON(audit ?? [:], to: auditPath)
      } catch {
        writeFailure("accessibility audit write failed: \(error)")
      }
    }

    let elapsed = (ProcessInfo.processInfo.systemUptime - launchUptime) * 1_000
    let metrics: [String: Any] = [
      "launch_to_evidence_ready_ms": elapsed,
      "model_loaded": model.hasLoaded,
      "screenshot_bytes": screenshotBytes,
      "screenshot_error": screenshotError as Any,
      "accessibility_audit_passed": audit?["audit_passed"] as? Bool ?? false,
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

  private static func auditApplicationAccessibility(pid: pid_t) async -> [String: Any] {
    await Task.detached(priority: .userInitiated) { () -> AccessibilityAuditPayload in
      auditAXTree(application: AXUIElementCreateApplication(pid))
    }.value.values
  }

  nonisolated private static func auditAXTree(application: AXUIElement) -> AccessibilityAuditPayload {
    var roleCounts: [String: Int] = [:]
    var issues: [String] = []
    var visited = Set<CFHashCode>()
    var elementCount = 0
    var windowCount = 0

    func stringAttribute(_ element: AXUIElement, _ name: String) -> String {
      var value: CFTypeRef?
      guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
        return ""
      }
      return value as? String ?? ""
    }

    func boolAttribute(_ element: AXUIElement, _ name: String) -> Bool? {
      var value: CFTypeRef?
      guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
        return nil
      }
      return value as? Bool
    }

    func sizeAttribute(_ element: AXUIElement) -> CGSize? {
      var value: CFTypeRef?
      guard AXUIElementCopyAttributeValue(element, "AXSize" as CFString, &value) == .success,
            let value,
            CFGetTypeID(value) == AXValueGetTypeID() else {
        return nil
      }
      var size = CGSize.zero
      guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
      return size
    }

    func actions(_ element: AXUIElement) -> [String] {
      var names: CFArray?
      guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
      return names as? [String] ?? []
    }

    func visit(_ element: AXUIElement, depth: Int) {
      guard depth <= 30, elementCount < 10_000 else { return }
      let hash = CFHash(element)
      guard visited.insert(hash).inserted else { return }
      elementCount += 1

      let role = stringAttribute(element, "AXRole")
      roleCounts[role, default: 0] += 1
      if role == "AXWindow" { windowCount += 1 }

      let interactiveRoles: Set<String> = [
        "AXButton",
        "AXCheckBox",
        "AXLink",
        "AXMenuButton",
        "AXPopUpButton",
        "AXRadioButton",
        "AXSlider",
        "AXTextField",
      ]
      if interactiveRoles.contains(role) {
        let label = [
          stringAttribute(element, "AXTitle"),
          stringAttribute(element, "AXDescription"),
          stringAttribute(element, "AXHelp"),
          stringAttribute(element, "AXValue"),
        ].first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? ""
        if label.isEmpty {
          issues.append("\(role) has no accessible label")
        }
        if let size = sizeAttribute(element), size.width < 24 || size.height < 24 {
          issues.append("\(role) target is smaller than 24x24")
        }
        let actionableRoles: Set<String> = [
          "AXButton",
          "AXCheckBox",
          "AXMenuButton",
          "AXPopUpButton",
          "AXRadioButton",
        ]
        if actionableRoles.contains(role), actions(element).isEmpty, boolAttribute(element, "AXEnabled") != false {
          issues.append("\(role) exposes no accessibility action")
        }
      }

      var childrenValue: CFTypeRef?
      if AXUIElementCopyAttributeValue(element, "AXChildren" as CFString, &childrenValue) == .success,
         let children = childrenValue as? [AXUIElement] {
        for child in children {
          visit(child, depth: depth + 1)
        }
      }
    }

    visit(application, depth: 0)
    if windowCount == 0 { issues.append("application exposes no accessibility window") }
    return AccessibilityAuditPayload(values: [
      "audit_passed": issues.isEmpty,
      "issue_count": issues.count,
      "issues": Array(Set(issues)).sorted(),
      "element_count": elementCount,
      "window_count": windowCount,
      "role_counts": roleCounts,
      "scope": "self-ax-tree",
    ])
  }

}

private enum EvidenceError: Error {
  case message(String)
}

private struct AccessibilityAuditPayload: @unchecked Sendable {
  let values: [String: Any]
}
