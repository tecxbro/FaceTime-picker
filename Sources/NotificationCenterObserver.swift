#if os(macOS)
@preconcurrency import AppKit
@preconcurrency import ApplicationServices
@preconcurrency import Contacts
import Darwin
import Foundation

extension NotificationCenterMonitor {
  func registerNotifications(on element: AXUIElement) {
    guard let observer else { return }
    let refcon = Unmanaged.passUnretained(self).toOpaque()

    for notification in observedNotifications {
      let key = RegistrationKey(
        element: elementIdentity(element),
        notification: notification as String
      )
      if successfulRegistrations.contains(key) || unsupportedRegistrations.contains(key)
        || exhaustedRegistrations.contains(key)
      {
        continue
      }
      guard registrationAttempts.count < maxObserverRegistrationPairs else { return }

      let attempts = registrationAttempts[key, default: 0]
      guard attempts < 2 else {
        exhaustedRegistrations.insert(key)
        continue
      }
      registrationAttempts[key] = attempts + 1

      let result = AXObserverAddNotification(observer, element, notification, refcon)
      if result == .success || result == .notificationAlreadyRegistered {
        successfulRegistrations.insert(key)
      } else if result == .notificationUnsupported {
        unsupportedRegistrations.insert(key)
      } else {
        registrationFailureCount += 1
        if attempts + 1 >= 2 {
          exhaustedRegistrations.insert(key)
        }
        if registrationFailureSamples < maxRegistrationFailureSamples {
          registrationFailureSamples += 1
          logLine(
            "AX REGISTRATION WARNING notification=\(notification as String) "
              + "axError=\(result.rawValue) attempt=\(attempts + 1)"
          )
        }
      }
    }
  }

  func isPlausiblePollRoot(_ element: AXUIElement) -> Bool {
    let role = axString(element, kAXRoleAttribute as CFString) ?? ""
    let subrole = axString(element, kAXSubroleAttribute as CFString) ?? ""
    if role == "AXApplication" || role == "AXMenu" || role == "AXMenuBar" || role == "AXMenuItem"
    {
      return false
    }
    if subrole.localizedCaseInsensitiveContains("dialog") { return true }
    switch role {
    case "AXWindow", "AXGroup", "AXPopover", "AXSheet", "AXScrollArea", "AXList":
      return true
    default:
      let text = readableText(element)
      return looksLikeFaceTimeMarker(text) || looksLikeAnswerLabel(text)
        || looksLikeDeclineLabel(text)
    }
  }

  func pollRootPriority(_ element: AXUIElement, isNew: Bool) -> Int {
    let role = axString(element, kAXRoleAttribute as CFString) ?? ""
    let subrole = axString(element, kAXSubroleAttribute as CFString) ?? ""
    let text = readableText(element)
    var score = isNew ? 1_000 : 0

    if looksLikeAnswerLabel(text) || looksLikeDeclineLabel(text) { score += 700 }
    if looksLikeFaceTimeMarker(text) { score += 650 }
    if identity.match(texts: [text]).source != .none { score += 600 }
    if subrole.localizedCaseInsensitiveContains("dialog") { score += 400 }
    switch role {
    case "AXPopover", "AXSheet": score += 300
    case "AXWindow": score += 250
    case "AXGroup": score += 100
    case "AXScrollArea", "AXList": score += 25
    default: break
    }
    return score
  }

  func focusedPollRoots() -> [AXUIElement] {
    var rawTopLevel: [AXUIElement] = []
    var topSeen: Set<AXElementIdentity> = []

    func appendTop(_ element: AXUIElement?) {
      guard let element else { return }
      let key = elementIdentity(element)
      if topSeen.insert(key).inserted {
        rawTopLevel.append(element)
      }
    }

    for window in axElementArray(appElement, kAXWindowsAttribute as CFString) {
      appendTop(window)
    }
    appendTop(axElement(appElement, kAXFocusedWindowAttribute as CFString))
    appendTop(axElement(appElement, kAXMainWindowAttribute as CFString))
    for child in axChildrenUnion(appElement) {
      appendTop(child)
    }

    var candidates: [AXUIElement] = []
    var candidateSeen: Set<AXElementIdentity> = []
    func appendCandidate(_ element: AXUIElement) {
      guard isPlausiblePollRoot(element) else { return }
      let key = elementIdentity(element)
      if candidateSeen.insert(key).inserted {
        candidates.append(element)
      }
    }

    for top in rawTopLevel.prefix(48) {
      appendCandidate(top)
      for child in axChildrenUnion(top).prefix(64) {
        appendCandidate(child)
      }
    }

    let currentIdentities = Set(candidates.map(elementIdentity))
    let ranked = candidates.map { element in
      RankedRoot(
        element: element,
        priority: pollRootPriority(
          element,
          isNew: !previousPollRoots.contains(elementIdentity(element))
        )
      )
    }.sorted { lhs, rhs in
      if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
      return CFHash(lhs.element) < CFHash(rhs.element)
    }
    previousPollRoots = currentIdentities
    return ranked.prefix(focusedPollRootLimit).map(\.element)
  }

  func refreshObserverRegistrations(around roots: [AXUIElement]) {
    for root in roots.prefix(32) {
      registerNotifications(on: root)
      for child in axChildrenUnion(root).prefix(16) {
        registerNotifications(on: child)
      }
    }
  }

  func startTimers() {
    focusedPollTimer = Timer.scheduledTimer(withTimeInterval: focusedPollInterval, repeats: true)
    { [weak self] _ in
      self?.pollFocusedWindows()
    }
    heartbeatTimer = Timer.scheduledTimer(withTimeInterval: heartbeatInterval, repeats: true) {
      [weak self] _ in
      self?.printHeartbeat()
    }
    activeCallTimer = Timer.scheduledTimer(
      withTimeInterval: activeCallCheckInterval, repeats: true
    ) { [weak self] _ in
      self?.recheckActiveCall()
    }
  }

  func printHeartbeat() {
    logLine(
      "HEARTBEAT callbacks=\(callbackCount) scans=\(scanCount) candidates=\(candidateCount) "
        + "detections=\(detectionCount) deduplicated=\(deduplicatedCount) "
        + "windowPolls=\(focusedPollCount) pollSkipped=\(focusedPollSkippedCount) "
        + "pollRoots=\(focusedPollRootCount) budgetStops=\(focusedPollBudgetStops) "
        + "registeredPairs=\(successfulRegistrations.count) unsupportedPairs=\(unsupportedRegistrations.count) "
        + "registrationFailures=\(registrationFailureCount) actions=\(actionCount)"
    )
  }

  func enqueue(_ signal: EventSignal) {
    pendingSignal = signal
    guard !isInspecting else { return }
    isInspecting = true

    while let next = pendingSignal {
      pendingSignal = nil
      inspect(signal: next)
    }
    isInspecting = false
  }

}

#endif
