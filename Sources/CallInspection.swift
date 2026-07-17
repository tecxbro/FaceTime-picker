#if os(macOS)
@preconcurrency import AppKit
@preconcurrency import ApplicationServices
@preconcurrency import Contacts
import Darwin
import Foundation

struct AXRecord {
  let element: AXUIElement
  let role: String
  let subrole: String
  let text: String
  let pressable: Bool
}

struct CallSnapshot {
  let root: AXUIElement
  let rootRole: String
  let rootSubrole: String
  let fingerprint: String
  let callerText: String
  let identityMatch: IdentityMatch
  let answerControl: AXUIElement?
  let declineControl: AXUIElement?
  let hasFaceTimeMarker: Bool
  let hasContainerSignature: Bool
  let hasHangUp: Bool
  let nodesScanned: Int
  let scanMilliseconds: Double
  let identityMilliseconds: Double

  var evidenceScore: Int {
    var score = 0
    if hasFaceTimeMarker { score += 2 }
    if hasContainerSignature { score += 1 }
    if answerControl != nil { score += 2 }
    if declineControl != nil { score += 2 }
    if callerText != "unavailable" { score += 1 }
    if identityMatch.source != .none { score += 2 }
    return score
  }

  var isCallLikeCandidate: Bool {
    evidenceScore >= 4
      && (hasFaceTimeMarker || answerControl != nil || declineControl != nil
        || identityMatch.source != .none)
  }

  var isStrongIncomingCall: Bool {
    let identityOrFaceTime = hasFaceTimeMarker || identityMatch.source != .none
    return identityOrFaceTime && hasContainerSignature && answerControl != nil
      && declineControl != nil && callerText != "unavailable"
  }
}

func subtreeText(_ root: AXUIElement, maxDepth: Int, maxNodes: Int) -> [String] {
  var queue: [(AXUIElement, Int)] = [(root, 0)]
  var cursor = 0
  var seen: Set<AXElementIdentity> = []
  var texts: [String] = []
  while cursor < queue.count && seen.count < maxNodes {
    let (element, depth) = queue[cursor]
    cursor += 1
    let key = elementIdentity(element)
    guard seen.insert(key).inserted else { continue }
    let text = readableText(element)
    if !text.isEmpty { texts.append(text) }
    if depth < maxDepth {
      for child in prioritizedAXChildren(element) {
        queue.append((child, depth + 1))
      }
    }
  }
  return texts
}

func inspectCandidate(root: AXUIElement, identity: TrustedIdentityIndex) -> CallSnapshot {
  let scanStarted = nowNanoseconds()
  _ = AXUIElementSetMessagingTimeout(root, accessibilityTimeout)
  let rootRole = axString(root, kAXRoleAttribute as CFString) ?? ""
  let rootSubrole = axString(root, kAXSubroleAttribute as CFString) ?? ""

  var queue: [(AXUIElement, Int)] = [(root, 0)]
  var cursor = 0
  var seen: Set<AXElementIdentity> = []
  var records: [AXRecord] = []
  var texts: [String] = []
  var answerControl: AXUIElement?
  var declineControl: AXUIElement?
  var hasFaceTimeMarker = false
  var hasContainerSignature = false
  var hasHangUp = false

  while cursor < queue.count && seen.count < maxCandidateNodes {
    let (element, depth) = queue[cursor]
    cursor += 1
    let key = elementIdentity(element)
    guard seen.insert(key).inserted else { continue }

    let role = axString(element, kAXRoleAttribute as CFString) ?? ""
    let subrole = axString(element, kAXSubroleAttribute as CFString) ?? ""
    if role == "AXApplication" || role == "AXMenu" || role == "AXMenuBar" || role == "AXMenuItem" {
      continue
    }

    let text = readableText(element)
    let pressable = supportsPress(element)
    records.append(AXRecord(element: element, role: role, subrole: subrole, text: text, pressable: pressable))
    if !text.isEmpty { texts.append(text) }

    if looksLikeFaceTimeMarker(text) { hasFaceTimeMarker = true }
    if looksLikeHangUpLabel(text) { hasHangUp = true }
    if role == "AXWindow" || role == "AXGroup" || role == "AXPopover" || role == "AXSheet"
      || subrole.localizedCaseInsensitiveContains("dialog")
      || normalizeSearchText(text).contains("notification center system dialog") {
      hasContainerSignature = true
    }
    if answerControl == nil && looksLikeAnswerLabel(text) {
      answerControl = nearestPressableAncestor(from: element)
    }
    if declineControl == nil && looksLikeDeclineLabel(text) {
      declineControl = nearestPressableAncestor(from: element)
    }

    if depth < maxCandidateDepth {
      for child in prioritizedAXChildren(element) { queue.append((child, depth + 1)) }
    }
  }

  if answerControl == nil || declineControl == nil {
    for record in records where record.pressable {
      let localTexts = [record.text] + subtreeText(record.element, maxDepth: 2, maxNodes: 18)
      if answerControl == nil && localTexts.contains(where: looksLikeAnswerLabel) { answerControl = record.element }
      if declineControl == nil && localTexts.contains(where: looksLikeDeclineLabel) { declineControl = record.element }
    }
  }

  let aggregateText = normalizeSearchText(texts.joined(separator: " "))
  if aggregateText.contains("facetime")
    && (aggregateText.contains("video") || aggregateText.contains("audio") || aggregateText.contains("call")) {
    hasFaceTimeMarker = true
  }

  let identityStarted = nowNanoseconds()
  let identityMatch = identity.match(texts: texts)
  let callerText = cleanedCallerText(from: texts, identity: identity)
  let identityMs = milliseconds(from: identityStarted)
  let scanMs = milliseconds(from: scanStarted)

  let fingerprintParts = [
    normalizeSearchText(callerText), identityMatch.source.rawValue,
    answerControl == nil ? "no-answer" : "answer",
    declineControl == nil ? "no-decline" : "decline",
    hasFaceTimeMarker ? "facetime" : "no-facetime",
  ]

  return CallSnapshot(
    root: root, rootRole: rootRole, rootSubrole: rootSubrole,
    fingerprint: fingerprintParts.joined(separator: "|"), callerText: callerText,
    identityMatch: identityMatch, answerControl: answerControl, declineControl: declineControl,
    hasFaceTimeMarker: hasFaceTimeMarker, hasContainerSignature: hasContainerSignature,
    hasHangUp: hasHangUp, nodesScanned: seen.count, scanMilliseconds: scanMs,
    identityMilliseconds: identityMs
  )
}

#endif
