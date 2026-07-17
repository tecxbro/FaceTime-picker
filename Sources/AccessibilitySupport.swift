#if os(macOS)
@preconcurrency import AppKit
@preconcurrency import ApplicationServices
@preconcurrency import Contacts
import Darwin
import Foundation

func axCopy(_ element: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
  var value: CFTypeRef?
  let result = AXUIElementCopyAttributeValue(element, attribute, &value)
  return result == .success ? value : nil
}

func axString(_ element: AXUIElement, _ attribute: CFString) -> String? {
  guard let value = axCopy(element, attribute) else { return nil }
  if let string = value as? String { return string }
  if let attributed = value as? NSAttributedString { return attributed.string }
  return nil
}

func axElement(_ element: AXUIElement, _ attribute: CFString) -> AXUIElement? {
  guard let value = axCopy(element, attribute),
    CFGetTypeID(value) == AXUIElementGetTypeID()
  else {
    return nil
  }
  return unsafeDowncast(value, to: AXUIElement.self)
}

func axElementArray(_ element: AXUIElement, _ attribute: CFString) -> [AXUIElement] {
  guard let value = axCopy(element, attribute),
    CFGetTypeID(value) == CFArrayGetTypeID()
  else {
    return []
  }

  let array = unsafeDowncast(value, to: CFArray.self)
  var output: [AXUIElement] = []
  output.reserveCapacity(CFArrayGetCount(array))
  for index in 0..<CFArrayGetCount(array) {
    guard let pointer = CFArrayGetValueAtIndex(array, index) else { continue }
    let object = unsafeBitCast(pointer, to: CFTypeRef.self)
    if CFGetTypeID(object) == AXUIElementGetTypeID() {
      output.append(unsafeDowncast(object, to: AXUIElement.self))
    }
  }
  return output
}

func axActionNames(_ element: AXUIElement) -> [String] {
  var names: CFArray?
  guard AXUIElementCopyActionNames(element, &names) == .success,
    let names
  else { return [] }
  return (names as NSArray).compactMap { $0 as? String }
}

func supportsPress(_ element: AXUIElement) -> Bool {
  axActionNames(element).contains(kAXPressAction as String)
}

struct AXElementIdentity: Hashable {
  let element: AXUIElement

  static func == (lhs: AXElementIdentity, rhs: AXElementIdentity) -> Bool {
    CFEqual(lhs.element, rhs.element)
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(CFHash(element))
  }
}

func elementIdentity(_ element: AXUIElement) -> AXElementIdentity {
  AXElementIdentity(element: element)
}

func elementKey(_ element: AXUIElement) -> String {
  String(CFHash(element))
}

func axChildrenUnion(_ element: AXUIElement) -> [AXUIElement] {
  let attributes: [CFString] = [
    kAXVisibleChildrenAttribute as CFString,
    kAXChildrenAttribute as CFString,
    "AXContents" as CFString,
    "AXChildrenInNavigationOrder" as CFString,
  ]
  var output: [AXUIElement] = []
  var seen: Set<AXElementIdentity> = []
  for attribute in attributes {
    for child in axElementArray(element, attribute) {
      let key = elementIdentity(child)
      if seen.insert(key).inserted {
        output.append(child)
      }
    }
  }
  return output
}

func axTopLevelChildrenUnion(_ element: AXUIElement) -> [AXUIElement] {
  var output = axChildrenUnion(element)
  var seen = Set(output.map { elementIdentity($0) })

  for child in axElementArray(element, kAXWindowsAttribute as CFString) {
    let key = elementIdentity(child)
    if seen.insert(key).inserted {
      output.append(child)
    }
  }
  if let focusedWindow = axElement(element, kAXFocusedWindowAttribute as CFString) {
    let key = elementIdentity(focusedWindow)
    if seen.insert(key).inserted {
      output.append(focusedWindow)
    }
  }
  return output
}

func candidateChildPriority(_ element: AXUIElement) -> Int {
  let role = axString(element, kAXRoleAttribute as CFString) ?? ""
  let subrole = axString(element, kAXSubroleAttribute as CFString) ?? ""
  let text = readableText(element)
  var score = 0

  if looksLikeAnswerLabel(text) || looksLikeDeclineLabel(text) || looksLikeFaceTimeMarker(text) {
    score += 500
  }
  if subrole.localizedCaseInsensitiveContains("dialog") {
    score += 300
  }
  switch role {
  case "AXWindow", "AXPopover", "AXSheet": score += 220
  case "AXGroup": score += 80
  case "AXButton": score += 60
  case "AXStaticText": score += 20
  default: break
  }
  return score
}

func prioritizedAXChildren(_ element: AXUIElement) -> [AXUIElement] {
  axChildrenUnion(element).enumerated().sorted { lhs, rhs in
    let leftScore = candidateChildPriority(lhs.element)
    let rightScore = candidateChildPriority(rhs.element)
    if leftScore != rightScore { return leftScore > rightScore }
    return lhs.offset < rhs.offset
  }.map(\.element)
}

func readableText(_ element: AXUIElement) -> String {
  let attributes: [CFString] = [
    kAXTitleAttribute as CFString,
    kAXDescriptionAttribute as CFString,
    kAXValueAttribute as CFString,
    kAXHelpAttribute as CFString,
    "AXLabel" as CFString,
    "AXAttributedDescription" as CFString,
    "AXPlaceholderValue" as CFString,
  ]

  var parts: [String] = []
  var seen: Set<String> = []
  for attribute in attributes {
    guard
      let value = axString(element, attribute)?.trimmingCharacters(in: .whitespacesAndNewlines),
      !value.isEmpty,
      normalizeSearchText(value) != "missing value"
    else { continue }
    if seen.insert(value).inserted {
      parts.append(value)
    }
  }
  return parts.joined(separator: " ")
}

func nearestPressableAncestor(from element: AXUIElement, limit: Int = 6) -> AXUIElement? {
  var current: AXUIElement? = element
  var seen: Set<AXElementIdentity> = []
  for _ in 0..<limit {
    guard let item = current else { return nil }
    let key = elementIdentity(item)
    guard seen.insert(key).inserted else { return nil }
    if supportsPress(item) { return item }
    current = axElement(item, kAXParentAttribute as CFString)
  }
  return nil
}

#endif
