import ApplicationServices
import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 3,
      let pid = pid_t(CommandLine.arguments[1])
else {
  fputs("usage: audit-macos-accessibility <pid> <output.json>\n", stderr)
  exit(2)
}

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
  var value: CFTypeRef?
  return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func stringAttribute(_ element: AXUIElement, _ name: String) -> String {
  attribute(element, name) as? String ?? ""
}

func sizeAttribute(_ element: AXUIElement) -> CGSize? {
  guard let value = attribute(element, "AXSize"),
        CFGetTypeID(value) == AXValueGetTypeID()
  else {
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

let expectedIdentifiers: Set<String> = [
  "filter-button",
  "schedule-density",
  "schedule-next",
  "schedule-previous",
  "schedule-settings",
  "schedule-today",
  "settings-button",
  "sort-menu",
  "toolbar-add-task",
]
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
let actionableRoles: Set<String> = [
  "AXButton",
  "AXCheckBox",
  "AXMenuButton",
  "AXPopUpButton",
  "AXRadioButton",
]
let nativeWindowChrome: Set<String> = [
  "AXCloseButton",
  "AXFullScreenButton",
  "AXMinimizeButton",
  "AXZoomButton",
]
let nativeStepper: Set<String> = ["AXDecrementArrow", "AXIncrementArrow"]

var roleCounts: [String: Int] = [:]
var issues: [String] = []
var exemptions: [String: Int] = [:]
var identifiers = Set<String>()
var visited = Set<CFHashCode>()
var elementCount = 0
var interactiveElementCount = 0
var windowCount = 0

func visit(_ element: AXUIElement, depth: Int) {
  guard depth <= 30, elementCount < 10_000 else { return }
  let hash = CFHash(element)
  guard visited.insert(hash).inserted else { return }
  elementCount += 1

  let role = stringAttribute(element, "AXRole")
  let subrole = stringAttribute(element, "AXSubrole")
  let identifier = stringAttribute(element, "AXIdentifier")
  roleCounts[role, default: 0] += 1
  if !identifier.isEmpty { identifiers.insert(identifier) }
  if role == "AXWindow" { windowCount += 1 }

  if interactiveRoles.contains(role) {
    interactiveElementCount += 1
    let label = [
      stringAttribute(element, "AXTitle"),
      stringAttribute(element, "AXDescription"),
      stringAttribute(element, "AXHelp"),
      stringAttribute(element, "AXValue"),
      stringAttribute(element, "AXPlaceholderValue"),
    ].first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? ""

    if nativeWindowChrome.contains(subrole) {
      exemptions["native-window-chrome", default: 0] += 1
    } else if nativeStepper.contains(subrole) {
      exemptions["native-stepper", default: 0] += 1
    } else if label.isEmpty {
      issues.append("\(role) id=\(identifier) subrole=\(subrole) has no accessible label")
    }

    if !nativeWindowChrome.contains(subrole), !nativeStepper.contains(subrole),
       let size = sizeAttribute(element),
       size.width < 20 || size.height < 20 {
      issues.append(
        "\(role) id=\(identifier) target is smaller than 20x20: "
          + "\(Int(size.width))x\(Int(size.height))"
      )
    }

    if actionableRoles.contains(role), actions(element).isEmpty {
      issues.append("\(role) id=\(identifier) exposes no accessibility action")
    }
  }

  if let children = attribute(element, "AXChildren") as? [AXUIElement] {
    for child in children {
      visit(child, depth: depth + 1)
    }
  }
}

visit(AXUIElementCreateApplication(pid), depth: 0)
if windowCount == 0 {
  issues.append("application exposes no accessibility window")
}
let missingIdentifiers = expectedIdentifiers.subtracting(identifiers).sorted()
for identifier in missingIdentifiers {
  issues.append("core accessibility identifier is missing: \(identifier)")
}

let payload: [String: Any] = [
  "audit_passed": issues.isEmpty,
  "element_count": elementCount,
  "exemptions": exemptions,
  "expected_identifiers": expectedIdentifiers.sorted(),
  "interactive_element_count": interactiveElementCount,
  "issue_count": issues.count,
  "issues": Array(Set(issues)).sorted(),
  "missing_identifiers": missingIdentifiers,
  "role_counts": roleCounts,
  "scope": "external-ax-tree",
  "window_count": windowCount,
]
let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
print(String(data: data, encoding: .utf8)!)
