#if os(macOS)
@preconcurrency import AppKit
@preconcurrency import ApplicationServices
@preconcurrency import Contacts
import Darwin
import Foundation

extension NotificationCenterMonitor {
  func processDetectedCall(_ call: CallSnapshot, signal: EventSignal, cumulativeScanMs: Double, inspectionStarted: UInt64) {
    let detectionAt = nowNanoseconds()
    let eventToDetection = milliseconds(from: signal.receivedAt, to: detectionAt)
    let totalInternal = milliseconds(from: inspectionStarted, to: detectionAt)

    // Observer callbacks and the polling fallback can report the same call. The
    // cooldown and fingerprint checks prevent repeated Answer/Decline presses.
    if lastActionAt != 0 && milliseconds(from: lastActionAt, to: detectionAt) < recentActionCooldownMs {
      deduplicatedCount += 1
      return
    }
    if activeCall?.fingerprint == call.fingerprint {
      deduplicatedCount += 1
      activeCall?.root = call.root
      activeCall?.missingChecks = 0
      return
    }

    pendingUnverifiedCall = nil
    detectionCount += 1
    activeCall = ActiveCall(fingerprint: call.fingerprint, root: call.root, missingChecks: 0, actionTaken: false)

    logLine(
      "CALL DETECTED \(callerLogFields(for: call)) numberMatch=\(call.identityMatch.isTrusted) "
        + "matchSource=\(call.identityMatch.source.rawValue) answerControl=\(call.answerControl != nil) "
        + "declineControl=\(call.declineControl != nil) source=NotificationCenter event=\(signal.eventName) "
        + String(format: "eventToDetectionMs=%.2f scanMs=%.2f identityMs=%.2f totalInternalMs=%.2f nodes=%d",
          eventToDetection, cumulativeScanMs, call.identityMilliseconds, totalInternal, call.nodesScanned)
    )

    switch mode {
    case .detector:
      return
    case .answerTrusted:
      guard call.identityMatch.isTrusted, let answer = call.answerControl else { return }
      performAction(control: answer, actionName: "answer", successMessage: "TRUSTED CALL ACCEPTED",
        failureMessage: "ANSWER PRESS FAILED", reason: nil, call: call, signal: signal,
        eventToDetection: eventToDetection)
    case .gatekeeper:
      switch gatekeeperIdentityDecision(identityMatch: call.identityMatch, callerText: call.callerText) {
      case .answerTrusted:
        if let answer = call.answerControl {
          performAction(control: answer, actionName: "answer", successMessage: "TRUSTED CALL ACCEPTED",
            failureMessage: "ANSWER PRESS FAILED", reason: "trustedIdentity", call: call,
            signal: signal, eventToDetection: eventToDetection)
        }
      case .declineNonMatch:
        if let decline = call.declineControl {
          let reason = call.identityMatch.source == .ambiguousContactAlias ? "ambiguousContactAlias" : "numberDidNotMatch"
          performAction(control: decline, actionName: "decline", successMessage: "UNTRUSTED CALL DECLINED",
            failureMessage: "DECLINE PRESS FAILED", reason: reason, call: call,
            signal: signal, eventToDetection: eventToDetection)
        }
      case .waitForIdentity:
        trackUnverifiedCandidateIfNeeded(call)
      }
    }
  }

  func performAction(control: AXUIElement, actionName: String, successMessage: String,
    failureMessage: String, reason: String?, call: CallSnapshot, signal: EventSignal,
    eventToDetection: Double) {
    let pressStarted = nowNanoseconds()
    let pressResult = AXUIElementPerformAction(control, kAXPressAction as CFString)
    let pressMs = milliseconds(from: pressStarted)
    let actionTotal = milliseconds(from: signal.receivedAt)
    if pressResult == .success {
      actionCount += 1
      activeCall?.actionTaken = true
      lastActionAt = nowNanoseconds()
      let reasonText = reason.map { " reason=\($0)" } ?? ""
      logLine("\(successMessage) \(callerLogFields(for: call))\(reasonText) "
        + String(format: "eventToDetectionMs=%.2f matchMs=%.2f pressMs=%.2f totalInternalMs=%.2f",
          eventToDetection, call.identityMilliseconds, pressMs, actionTotal))
    } else {
      logLine("\(failureMessage) action=\(actionName) axError=\(pressResult.rawValue) \(callerLogFields(for: call))")
    }
  }

  func trackUnverifiedCandidateIfNeeded(_ call: CallSnapshot) {
    // Only a structurally complete incoming-call UI with missing caller identity
    // enters the grace path. Partial or unrelated Notification Center UI does not.
    guard mode == .gatekeeper, call.hasFaceTimeMarker, call.hasContainerSignature,
      call.answerControl != nil, call.declineControl != nil, call.callerText == "unavailable" else { return }
    let now = nowNanoseconds()
    if var pending = pendingUnverifiedCall {
      pending.root = call.root
      pending.lastSeenAt = now
      pending.missingChecks = 0
      pendingUnverifiedCall = pending
    } else {
      pendingUnverifiedCall = PendingUnverifiedCall(root: call.root, firstSeenAt: now, lastSeenAt: now, missingChecks: 0)
      logLine(String(format: "UNVERIFIED CALL PENDING identityGraceMs=%.0f", unverifiedIdentityGraceMs))
    }
  }

  func logPartialCandidate(_ call: CallSnapshot, signal: EventSignal, cumulativeScanMs: Double) {
    let now = nowNanoseconds()
    if lastCandidateFingerprint == call.fingerprint && milliseconds(from: lastCandidateLoggedAt, to: now) < 1_500 { return }
    lastCandidateFingerprint = call.fingerprint
    lastCandidateLoggedAt = now
    candidateCount += 1
    var missing: [String] = []
    if !call.hasFaceTimeMarker { missing.append("facetime") }
    if !call.hasContainerSignature { missing.append("container") }
    if call.answerControl == nil { missing.append("answer") }
    if call.declineControl == nil { missing.append("decline") }
    if call.callerText == "unavailable" { missing.append("caller") }
    logLine("CALL CANDIDATE \(callerLogFields(for: call)) numberMatch=\(call.identityMatch.isTrusted) "
      + "matchSource=\(call.identityMatch.source.rawValue) faceTime=\(call.hasFaceTimeMarker) "
      + "answerControl=\(call.answerControl != nil) declineControl=\(call.declineControl != nil) "
      + "container=\(call.hasContainerSignature) missing=\(missing.joined(separator: ",")) "
      + "source=NotificationCenter event=\(signal.eventName) rootRole=\(call.rootRole) rootSubrole=\(call.rootSubrole) "
      + String(format: "eventAgeMs=%.2f scanMs=%.2f nodes=%d score=%d",
        milliseconds(from: signal.receivedAt), cumulativeScanMs, call.nodesScanned, call.evidenceScore))
  }

  func recheckActiveCall() {
    if var pending = pendingUnverifiedCall {
      let checkStarted = nowNanoseconds()
      let snapshot = inspectCandidate(root: pending.root, identity: identity)
      if snapshot.isStrongIncomingCall && !snapshot.hasHangUp {
        pendingUnverifiedCall = nil
        processDetectedCall(snapshot,
          signal: EventSignal(element: snapshot.root, eventName: "IdentityGraceRecheck", receivedAt: checkStarted),
          cumulativeScanMs: snapshot.scanMilliseconds, inspectionStarted: checkStarted)
        return
      }
      let stillIncomingWithoutIdentity = snapshot.hasFaceTimeMarker && snapshot.hasContainerSignature
        && snapshot.answerControl != nil && snapshot.declineControl != nil && !snapshot.hasHangUp
      if stillIncomingWithoutIdentity {
        pending.root = snapshot.root
        pending.lastSeenAt = nowNanoseconds()
        pending.missingChecks = 0
        pendingUnverifiedCall = pending

        // The 900 ms window gives Notification Center time to populate delayed
        // caller text. If it remains absent, gatekeeper mode fails closed.
        if milliseconds(from: pending.firstSeenAt) >= unverifiedIdentityGraceMs, let decline = snapshot.declineControl {
          pendingUnverifiedCall = nil
          detectionCount += 1
          activeCall = ActiveCall(fingerprint: "unverified|\(snapshot.fingerprint)", root: snapshot.root,
            missingChecks: 0, actionTaken: false)
          let signal = EventSignal(element: snapshot.root, eventName: "IdentityGraceExpired", receivedAt: pending.firstSeenAt)
          performAction(control: decline, actionName: "decline", successMessage: "UNVERIFIED CALL DECLINED",
            failureMessage: "DECLINE PRESS FAILED", reason: "identityGraceExpired", call: snapshot,
            signal: signal, eventToDetection: milliseconds(from: pending.firstSeenAt))
        }
        return
      }
      pending.missingChecks += 1
      pendingUnverifiedCall = pending.missingChecks >= 5 ? nil : pending
    }

    guard var active = activeCall else { return }
    let snapshot = inspectCandidate(root: active.root, identity: identity)
    if snapshot.isStrongIncomingCall && !snapshot.hasHangUp {
      active.root = snapshot.root
      active.missingChecks = 0
      activeCall = active
      return
    }
    active.missingChecks += 1
    activeCall = active.missingChecks >= 3 ? nil : active
  }
}

#endif
