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

  init(source: ConfiguredTrustedCallerSource, sourceKind: String, refreshInterval: TimeInterval,
    maxStaleSeconds: TimeInterval, monitor: NotificationCenterMonitor) {
    self.source = source
    self.sourceKind = sourceKind
    self.refreshInterval = refreshInterval

    // Never expire a snapshot before the next scheduled refresh attempt. Without
    // this floor, a long provider TTL could create an avoidable trust blackout.
    self.maxStaleSeconds = max(maxStaleSeconds, refreshInterval)
    self.monitor = monitor
  }

  func start() {
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + refreshInterval, repeating: refreshInterval, leeway: .seconds(2))
    timer.setEventHandler { [weak self] in self?.refresh() }
    self.timer = timer
    timer.resume()
  }

  private func refresh() {
    // Slow endpoints must not create overlapping refreshes or reorder snapshots.
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
      if staleSeconds >= maxStaleSeconds, !failClosedApplied {
        failClosedApplied = true
        DispatchQueue.main.async { [weak self] in
          // Clearing the index is the fail-closed state: no caller can be
          // answered as trusted until a complete valid snapshot is loaded again.
          self?.monitor?.updateIdentity(.empty, source: "expiredFailClosed")
          logLine("IDENTITY CACHE EXPIRED. No callers are trusted until the identity source recovers.")
        }
      }
    }
  }
}
#endif
