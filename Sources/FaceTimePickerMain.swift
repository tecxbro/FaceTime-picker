#if os(macOS)
@preconcurrency import AppKit
@preconcurrency import ApplicationServices
@preconcurrency import Contacts
import Darwin
import Foundation

func ensureFaceTimeRunning() {
  let workspace = NSWorkspace.shared
  if let running = workspace.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.FaceTime" }) {
    _ = running.activate(options: [])
    return
  }
  guard let url = workspace.urlForApplication(withBundleIdentifier: "com.apple.FaceTime") else {
    writeError("FaceTime could not be located.")
    return
  }
  let configuration = NSWorkspace.OpenConfiguration()
  configuration.activates = true
  let semaphore = DispatchSemaphore(value: 0)
  workspace.openApplication(at: url, configuration: configuration) { _, error in
    if let error { writeError("Could not open FaceTime: \(error.localizedDescription)") }
    semaphore.signal()
  }
  _ = semaphore.wait(timeout: .now() + 8)
}

func notificationCenterApplication(timeout: TimeInterval = 8.0) -> NSRunningApplication? {
  let deadline = Date().addingTimeInterval(timeout)
  repeat {
    if let app = NSWorkspace.shared.runningApplications.first(where: {
      $0.bundleIdentifier == "com.apple.notificationcenterui"
        || ($0.localizedName ?? "").replacingOccurrences(of: " ", with: "") == "NotificationCenter"
    }) { return app }
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
  } while Date() < deadline
  return nil
}

@main
struct FaceTimePickerMain {
  static func main() {
    let configuration: Configuration
    do { configuration = try Configuration.parse(arguments: CommandLine.arguments) }
    catch { writeError(error.localizedDescription); exit(2) }

    // Action modes require both the requested mode and a separate acknowledgement
    // supplied by run.sh. Direct binary invocation cannot enable actions by mode alone.
    if configuration.mode != .detector && !configuration.confirmedEnable {
      writeError("Refusing to enable call actions without the launcher's explicit confirmation.")
      exit(2)
    }

    let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    // macOS displays this permission prompt asynchronously. Exiting here avoids
    // running a partially authorized monitor; the user grants access and reruns.
    guard AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary) else {
      writeError("Accessibility permission is missing. Add the compiled FaceTimePicker executable under System Settings → Privacy & Security → Accessibility, enable it, then run again.")
      exit(3)
    }

    // Monitoring starts only after a complete valid snapshot is available. This
    // prevents a transient source failure from being interpreted as an empty allowlist.
    let source = ConfiguredTrustedCallerSource(configuration: configuration.identitySource)
    let callerSnapshot: TrustedCallerSnapshot
    do { callerSnapshot = try source.load() }
    catch { writeError("Trusted-caller source failed: \(error.localizedDescription)"); exit(4) }

    let contactResolution = resolveTrustedIdentitiesOffMain(numbers: callerSnapshot.phoneNumbers)
    if let warning = contactResolution.warning { logLine("WARNING \(warning)") }
    ensureFaceTimeRunning()

    logLine("BUILD facetime-picker-v1-provider-agnostic")
    logLine("TRUSTED IDENTITIES LOADED source=\(configuration.identitySource.sourceKind) "
      + "callerCount=\(contactResolution.index.configuredNumbers.count) "
      + "matchingContactCount=\(contactResolution.index.matchingContactCount) "
      + "uniqueAliasCount=\(contactResolution.index.uniqueAliases.count) "
      + "ambiguousAliasCount=\(contactResolution.index.ambiguousAliases.count)")
    if configuration.logCallerText { logLine("PRIVACY WARNING raw caller text logging is enabled for this run.") }

    guard let notificationCenter = notificationCenterApplication() else {
      writeError("Notification Center process was not found."); exit(5)
    }
    guard let monitor = NotificationCenterMonitor(app: notificationCenter,
      identity: contactResolution.index, mode: configuration.mode,
      logCallerText: configuration.logCallerText) else { exit(6) }

    let refreshInterval = configuration.refreshSecondsOverride
      ?? TimeInterval(callerSnapshot.suggestedTTLSeconds ?? 300)
    let refresher = IdentityRefreshCoordinator(source: source,
      sourceKind: configuration.identitySource.sourceKind, refreshInterval: refreshInterval,
      maxStaleSeconds: configuration.maxStaleSeconds, monitor: monitor)
    refresher.start()
    logLine("IDENTITY REFRESH READY intervalSeconds=\(Int(refreshInterval)) maxStaleSeconds=\(Int(configuration.maxStaleSeconds))")

    switch configuration.mode {
    case .detector:
      logLine("READ-ONLY DETECTOR ENABLED. No calls will be answered or declined. Press Control+C to stop.")
    case .answerTrusted:
      logLine("TRUSTED AUTO-ANSWER ENABLED. Unknown or ambiguous callers are left ringing. Press Control+C to stop.")
    case .gatekeeper:
      logLine("FULL GATEKEEPER ENABLED. Trusted calls are answered. Non-matching, ambiguous, or unverified calls are declined. Press Control+C to stop.")
    }

    // The monitor owns AX callbacks and the refresher owns its dispatch timer.
    // Extend both lifetimes for the duration of the main run loop.
    withExtendedLifetime((monitor, refresher)) { RunLoop.main.run() }
  }
}
#endif
