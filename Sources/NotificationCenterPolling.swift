#if os(macOS)
@preconcurrency import AppKit
@preconcurrency import ApplicationServices
@preconcurrency import Contacts
import Darwin
import Foundation

extension NotificationCenterMonitor {
  func candidateRoots(from eventElement: AXUIElement) -> [AXUIElement] {
    var output: [AXUIElement] = []
    var seen: Set<AXElementIdentity> = []

    func append(_ element: AXUIElement?) {
      guard let element else { return }
      let role = axString(element, kAXRoleAttribute as CFString) ?? ""
      guard role != "AXApplication", role != "AXMenu", role != "AXMenuBar", role != "AXMenuItem"
      else { return }
      let key = elementIdentity(element)
      if seen.insert(key).inserted {
        output.append(element)
      }
    }

    append(eventElement)
    var current: AXUIElement? = eventElement
    for _ in 0..<maxCandidateAncestors {
      guard let item = current else { break }
      current = axElement(item, kAXParentAttribute as CFString)
      append(current)
    }
    append(axElement(eventElement, kAXTopLevelUIElementAttribute as CFString))
    return output
  }

  func inspect(signal: EventSignal) {
    guard !app.isTerminated else {
      logLine("Notification Center terminated. Restart the helper.")
      exit(1)
    }

    let inspectionStarted = nowNanoseconds()
    var best: CallSnapshot?
    var bestPartial: CallSnapshot?
    var cumulativeScanMs = 0.0

    let roots = candidateRoots(from: signal.element)
    refreshObserverRegistrations(around: roots)

    for root in roots {
      scanCount += 1
      let snapshot = inspectCandidate(root: root, identity: identity)
      cumulativeScanMs += snapshot.scanMilliseconds
      if snapshot.isStrongIncomingCall {
        best = snapshot
        break
      }
      if snapshot.isCallLikeCandidate
        && (bestPartial == nil || snapshot.evidenceScore > bestPartial!.evidenceScore)
      {
        bestPartial = snapshot
      }
    }

    if let call = best {
      processDetectedCall(
        call,
        signal: signal,
        cumulativeScanMs: cumulativeScanMs,
        inspectionStarted: inspectionStarted
      )
    } else if let partial = bestPartial {
      trackUnverifiedCandidateIfNeeded(partial)
      logPartialCandidate(partial, signal: signal, cumulativeScanMs: cumulativeScanMs)
    }
  }

  func pollFocusedWindows() {
    guard !isPolling, !isInspecting else {
      focusedPollSkippedCount += 1
      return
    }
    isPolling = true
    defer { isPolling = false }

    let pollStarted = nowNanoseconds()
    focusedPollCount += 1
    let roots = focusedPollRoots()
    focusedPollRootCount = roots.count
    refreshObserverRegistrations(around: roots)

    var bestPartial: CallSnapshot?
    var cumulativeScanMs = 0.0

    for root in roots {
      if milliseconds(from: pollStarted) >= focusedPollTimeBudgetMs {
        focusedPollBudgetStops += 1
        break
      }

      scanCount += 1
      let snapshot = inspectCandidate(root: root, identity: identity)
      cumulativeScanMs += snapshot.scanMilliseconds
      if snapshot.isStrongIncomingCall {
        let signal = EventSignal(
          element: root,
          eventName: "FocusedWindowPoll",
          receivedAt: pollStarted
        )
        processDetectedCall(
          snapshot,
          signal: signal,
          cumulativeScanMs: cumulativeScanMs,
          inspectionStarted: pollStarted
        )
        return
      }
      if snapshot.isCallLikeCandidate
        && (bestPartial == nil || snapshot.evidenceScore > bestPartial!.evidenceScore)
      {
        bestPartial = snapshot
      }
    }

    if let partial = bestPartial {
      trackUnverifiedCandidateIfNeeded(partial)
      logPartialCandidate(
        partial,
        signal: EventSignal(
          element: partial.root,
          eventName: "FocusedWindowPoll",
          receivedAt: pollStarted
        ),
        cumulativeScanMs: cumulativeScanMs
      )
    }
  }

}

#endif
