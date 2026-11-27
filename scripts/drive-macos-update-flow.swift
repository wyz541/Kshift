import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 4,
      let pid = pid_t(CommandLine.arguments[1])
else {
  fputs("usage: drive-macos-update-flow <pid> <report.json> <screenshot.png>\n", stderr)
  exit(2)
}

let reportPath = CommandLine.arguments[2]
let screenshotPath = CommandLine.arguments[3]
let application = AXUIElementCreateApplication(pid)

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
  var value: CFTypeRef?
  return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func stringAttribute(_ element: AXUIElement, _ name: String) -> String {
  attribute(element, name) as? String ?? ""
}

func children(_ element: AXUIElement) -> [AXUIElement] {
  attribute(element, "AXChildren") as? [AXUIElement] ?? []
}

func findElement(
  in root: AXUIElement,
  depth: Int = 0,
  matching predicate: (AXUIElement) -> Bool
) -> AXUIElement? {
  guard depth <= 30 else { return nil }
  if predicate(root) { return root }
  for child in children(root) {
    if let found = findElement(in: child, depth: depth + 1, matching: predicate) {
      return found
    }
  }
  return nil
}

func element(identifier: String) -> AXUIElement? {
  findElement(in: application) {
    stringAttribute($0, "AXIdentifier") == identifier
  }
}

func element(text: String) -> AXUIElement? {
  findElement(in: application) { candidate in
    let values = [
      stringAttribute(candidate, "AXTitle"),
      stringAttribute(candidate, "AXValue"),
      stringAttribute(candidate, "AXDescription"),
    ]
    return values.contains(text)
  }
}

func waitForElement(
  identifier: String,
  timeout: TimeInterval
) -> AXUIElement? {
  let deadline = Date().addingTimeInterval(timeout)
  repeat {
    if let found = element(identifier: identifier) { return found }
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
  } while Date() < deadline
  return nil
}

func waitForText(_ text: String, timeout: TimeInterval) -> Bool {
  let deadline = Date().addingTimeInterval(timeout)
  repeat {
    if element(text: text) != nil { return true }
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
  } while Date() < deadline
  return false
}

func press(_ element: AXUIElement) -> Bool {
  AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
}

func windowNumber() -> CGWindowID? {
  let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
  let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
  let owned = windows.filter {
    ($0[kCGWindowOwnerPID as String] as? Int) == Int(pid)
      && ($0[kCGWindowLayer as String] as? Int) == 0
  }
  func area(_ item: [String: Any]) -> Double {
    guard let bounds = item[kCGWindowBounds as String] as? [String: Any],
          let width = bounds["Width"] as? Double,
          let height = bounds["Height"] as? Double,
          width >= 200, height >= 200
    else { return .greatestFiniteMagnitude }
    return width * height
  }
  let selected = owned.sorted { area($0) < area($1) }.first
  return (selected?[kCGWindowNumber as String] as? Int).map(CGWindowID.init)
}

func writeScreenshot() -> Bool {
  guard let number = windowNumber() else { return false }
  typealias WindowImageFunction = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
  guard let handle = dlopen(
    "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
    RTLD_LAZY
  ), let symbol = dlsym(handle, "CGWindowListCreateImage") else {
    return false
  }
  defer { dlclose(handle) }
  let createImage = unsafeBitCast(symbol, to: WindowImageFunction.self)
  guard let image = createImage(.null, 8, number, 9)?.takeRetainedValue() else {
    return false
  }
  let bitmap = NSBitmapImageRep(cgImage: image)
  guard let data = bitmap.representation(using: .png, properties: [:]) else { return false }
  return (try? data.write(to: URL(fileURLWithPath: screenshotPath), options: .atomic)) != nil
}

var report: [String: Any] = [
  "checked_at": ISO8601DateFormatter().string(from: Date()),
  "pid": Int(pid),
  "steps": [],
]

func finish(_ result: String, detail: String? = nil) -> Never {
  report["result"] = result
  if let detail { report["detail"] = detail }
  let data = try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
  try! data.write(to: URL(fileURLWithPath: reportPath), options: .atomic)
  print(String(data: data, encoding: .utf8)!)
  exit(result == "passed" ? 0 : 1)
}

NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateIgnoringOtherApps])

guard let settings = waitForElement(identifier: "settings-button", timeout: 15) else {
  finish("failed", detail: "settings-button was not found")
}
guard press(settings) else { finish("failed", detail: "settings-button was not pressable") }
report["steps"] = ["settings-opened"]

guard let check = waitForElement(identifier: "check-for-updates", timeout: 15) else {
  finish("failed", detail: "check-for-updates was not found")
}
guard press(check) else { finish("failed", detail: "check-for-updates was not pressable") }
report["steps"] = ["settings-opened", "check-requested"]

guard let install = waitForElement(identifier: "install-update", timeout: 30) else {
  if element(identifier: "update-failed") != nil {
    finish("failed", detail: "live update check failed")
  }
  if element(identifier: "update-incompatible") != nil {
    finish("failed", detail: "live update was incompatible")
  }
  finish("failed", detail: "install-update was not offered")
}
report["update_available"] = true
report["steps"] = ["settings-opened", "check-requested", "update-available"]

guard press(install) else { finish("failed", detail: "install-update was not pressable") }
guard let confirm = waitForElement(identifier: "confirm-install-update", timeout: 15)
  ?? element(text: "Continue")
else {
  finish("failed", detail: "update confirmation was not shown")
}
guard press(confirm) else { finish("failed", detail: "update confirmation was not pressable") }
report["steps"] = ["settings-opened", "check-requested", "update-available", "install-confirmed"]

guard waitForText("The approved installer was opened.", timeout: 120) else {
  if element(identifier: "update-failed") != nil {
    finish("failed", detail: "download or signature verification failed")
  }
  finish("failed", detail: "installer-opened state was not observed")
}
report["installer_opened"] = true
report["screenshot_written"] = writeScreenshot()
report["steps"] = ["settings-opened", "check-requested", "update-available", "install-confirmed", "installer-opened"]
finish("passed")
