import Foundation

enum IdentitySourceConfiguration: Equatable, Sendable {
  case terminal
  case sqlite(url: URL)

  static func fromEnvironment(
    _ environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> IdentitySourceConfiguration {
    // No path means the safest zero-setup option: ask for numbers in this Terminal session.
    guard
      let rawPath = environment["FACETIME_PICKER_SQLITE_PATH"]?.trimmingCharacters(
        in: .whitespacesAndNewlines),
      !rawPath.isEmpty
    else {
      return .terminal
    }

    let expandedPath = NSString(string: rawPath).expandingTildeInPath
    return .sqlite(url: URL(fileURLWithPath: expandedPath))
  }

  var sourceKind: String {
    switch self {
    case .terminal: return "terminal"
    case .sqlite: return "sqlite"
    }
  }

  var supportsRefresh: Bool {
    switch self {
    case .terminal: return false
    case .sqlite: return true
    }
  }
}
