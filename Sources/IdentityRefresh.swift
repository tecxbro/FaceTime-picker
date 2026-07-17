#if os(macOS)
@preconcurrency import AppKit
@preconcurrency import ApplicationServices
@preconcurrency import Contacts
import Darwin
import Foundation

final class IdentityRefreshCoordinator: @unchecked Sendable {
  private let source: ConfiguredTrustedCallerSource
  private let sourceKind: String
  private let refreshInterval: TimeInterval
  private let maxStaleSeconds: TimeInterval
  private weak var monitor: NotificationCenterMonitor?
  private let queue = DispatchQueue(label: "app.facetimepicker.identity-refresh", qos: .utility)
  private var timer: DispatchSourceTimer?
  private var lastSuccessfulRefresh = Date()
  private var isRefreshing = false
  private var failClosedApplied = false

  init(
    source: ConfiguredTrustedCallerSource,
    sourceKind: String,
    refreshInterval: TimeInterval,
    maxStaleSeconds: TimeInterval,
    monitor: NotificationCenterMonitor
  ) {
    self.source = source
    self.sourceKind = sourceKind
    self.refreshInterval = refreshInterval
    self.maxStaleSeconds = max(maxStaleSeconds, refreshInterval)
    self.monitor = monitor
  }

  func start() {
    // Database I/O and Contacts resolution stay off the main run loop used by Accessibility events.
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(
      deadline: .now() + refreshInterval,
      repeating: refreshInterval,
      leeway: .seconds(2)
    )
    timer.setEventHandler { [weak self] in self?.refresh() }
    self.timer = timer
    timer.resume()
  }

  private func refresh() {
    guard !isRefreshing else { return }
    isRefreshing = true
    defer { isRefreshing = false }

    do {
      let snapshot = try source.load()
      let resolution = resolveTrustedIdentities(numbers: snapshot.phoneNumbers)
      lastSuccessfulRefresh = Date()
      failClosedApplied = false
      DispatchQueue.main.async { [weak self] in
        guard let self, let monitor = self.monitor else { return }
        if let warning = resolution.warning { logLine("IDENTITY REFRESH WARNING \(warning)") }
        monitor.updateIdentity(resolution.index, source: self.sourceKind)
      }
    } catch {
      let staleSeconds = Date().timeIntervalSince(lastSuccessfulRefresh)
      logLine("IDENTITY REFRESH FAILED source=\(sourceKind) staleSeconds=\(Int(staleSeconds))")

      // Once the last good snapshot is too old, trusting nobody is safer than trusting stale data.
      if staleSeconds >= maxStaleSeconds, !failClosedApplied {
        failClosedApplied = true
        DispatchQueue.main.async { [weak self] in
          self?.monitor?.updateIdentity(.empty, source: "expiredFailClosed")
          logLine("IDENTITY CACHE EXPIRED. No callers are trusted until the identity source recovers.")
        }
      }
    }
  }
}
#endif
