#if os(macOS)
@preconcurrency import AppKit
@preconcurrency import ApplicationServices
@preconcurrency import Contacts
import Darwin
import Foundation

struct EventSignal {
  let element: AXUIElement
  let eventName: String
  let receivedAt: UInt64
}

struct ActiveCall {
  let fingerprint: String
  var root: AXUIElement
  var missingChecks: Int
  var actionTaken: Bool
}

struct PendingUnverifiedCall {
  var root: AXUIElement
  let firstSeenAt: UInt64
  var lastSeenAt: UInt64
  var missingChecks: Int
}

final class NotificationCenterMonitor: @unchecked Sendable {
  struct RegistrationKey: Hashable {
    let element: AXElementIdentity
    let notification: String
  }

  struct RankedRoot {
    let element: AXUIElement
    let priority: Int
  }

  let app: NSRunningApplication
  let appElement: AXUIElement
  var identity: TrustedIdentityIndex
  let mode: RunMode
  let logCallerText: Bool
  var observer: AXObserver?
  var focusedPollTimer: Timer?
  var heartbeatTimer: Timer?
  var activeCallTimer: Timer?

  var isInspecting = false
  var pendingSignal: EventSignal?
  var isPolling = false

  var registrationAttempts: [RegistrationKey: Int] = [:]
  var successfulRegistrations: Set<RegistrationKey> = []
  var unsupportedRegistrations: Set<RegistrationKey> = []
  var exhaustedRegistrations: Set<RegistrationKey> = []
  var registrationFailureSamples = 0
  var previousPollRoots: Set<AXElementIdentity> = []
  var activeCall: ActiveCall?
  var pendingUnverifiedCall: PendingUnverifiedCall?
  var lastActionAt: UInt64 = 0
  var lastCandidateFingerprint: String?
  var lastCandidateLoggedAt: UInt64 = 0

  var callbackCount = 0
  var scanCount = 0
  var detectionCount = 0
  var candidateCount = 0
  var deduplicatedCount = 0
  var focusedPollCount = 0
  var focusedPollSkippedCount = 0
  var focusedPollRootCount = 0
  var focusedPollBudgetStops = 0
  var registrationFailureCount = 0
  var actionCount = 0

  init?(
    app: NSRunningApplication, identity: TrustedIdentityIndex, mode: RunMode, logCallerText: Bool
  ) {
    self.app = app
    self.identity = identity
    self.mode = mode
    self.logCallerText = logCallerText
    self.appElement = AXUIElementCreateApplication(app.processIdentifier)
    _ = AXUIElementSetMessagingTimeout(appElement, accessibilityTimeout)

    var createdObserver: AXObserver?
    let createResult = AXObserverCreate(
      app.processIdentifier,
      { _, changedElement, notification, refcon in
        guard let refcon else { return }
        let monitor = Unmanaged<NotificationCenterMonitor>.fromOpaque(refcon)
          .takeUnretainedValue()
        monitor.callbackCount += 1
        monitor.enqueue(
          EventSignal(
            element: changedElement,
            eventName: notification as String,
            receivedAt: nowNanoseconds()
          ))
      }, &createdObserver)

    guard createResult == .success, let createdObserver else {
      writeError(
        "Could not create Notification Center AX observer (error \(createResult.rawValue)).")
      return nil
    }

    observer = createdObserver
    CFRunLoopAddSource(
      CFRunLoopGetMain(),
      AXObserverGetRunLoopSource(createdObserver),
      .defaultMode
    )

    registerNotifications(on: appElement)
    let initialRoots = focusedPollRoots()
    refreshObserverRegistrations(around: initialRoots)
    startTimers()
    logLine(
      "FOCUSED WINDOW POLL READY intervalMs=100 rootLimit=\(focusedPollRootLimit) "
        + "candidateNodeLimit=\(maxCandidateNodes) axTimeoutMs=\(Int(accessibilityTimeout * 1_000))"
    )
  }

  func updateIdentity(_ newIdentity: TrustedIdentityIndex, source: String) {
    precondition(Thread.isMainThread)
    identity = newIdentity
    activeCall = nil
    pendingUnverifiedCall = nil
    logLine(
      "TRUSTED IDENTITIES UPDATED source=\(source) callerCount=\(newIdentity.configuredNumbers.count) "
        + "uniqueAliasCount=\(newIdentity.uniqueAliases.count) ambiguousAliasCount=\(newIdentity.ambiguousAliases.count)"
    )
  }

  func callerLogFields(for call: CallSnapshot) -> String {
    let state = privacySafeCallerState(
      identityMatch: call.identityMatch, callerText: call.callerText)
    if logCallerText {
      return "callerState=\(state) callerText=\(quoteForLog(call.callerText))"
    }
    return "callerState=\(state)"
  }

  let observedNotifications: [CFString] = [
    kAXWindowCreatedNotification as CFString,
    kAXCreatedNotification as CFString,
    kAXLayoutChangedNotification as CFString,
    kAXValueChangedNotification as CFString,
    kAXTitleChangedNotification as CFString,
    kAXUIElementDestroyedNotification as CFString,
  ]
}

#endif
