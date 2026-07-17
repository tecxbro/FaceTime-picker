#if os(macOS)
import Foundation

enum RunMode: String {
  case detector
  case answerTrusted = "answer-trusted"
  case gatekeeper
}

struct Configuration {
  let mode: RunMode
  let confirmedEnable: Bool
  let logCallerText: Bool
  let refreshSecondsOverride: TimeInterval?
  let maxStaleSeconds: TimeInterval
  let identitySource: IdentitySourceConfiguration

  static func parse(
    arguments: [String], environment: [String: String] = ProcessInfo.processInfo.environment
  ) throws -> Configuration {
    var mode: RunMode = .detector
    var confirmed = false
    var logCallerText = false
    var refreshOverride: TimeInterval?
    var maxStaleSeconds = max(
      60, Double(environment["FACETIME_PICKER_MAX_STALE_SECONDS"] ?? "900") ?? 900)
    var index = 1

    while index < arguments.count {
      switch arguments[index] {
      case "--mode":
        guard index + 1 < arguments.count,
          let parsed = RunMode(rawValue: arguments[index + 1])
        else {
          throw ConfigurationError.invalidArguments
        }
        mode = parsed
        index += 2
      case "--confirmed-enable":
        confirmed = true
        index += 1
      case "--log-caller-text":
        logCallerText = true
        index += 1
      case "--refresh-seconds":
        guard index + 1 < arguments.count,
          let parsed = Double(arguments[index + 1]), parsed >= 5
        else {
          throw ConfigurationError.invalidArguments
        }
        refreshOverride = min(parsed, 86_400)
        index += 2
      case "--max-stale-seconds":
        guard index + 1 < arguments.count,
          let parsed = Double(arguments[index + 1]), parsed >= 60
        else {
          throw ConfigurationError.invalidArguments
        }
        maxStaleSeconds = min(parsed, 604_800)
        index += 2
      default:
        throw ConfigurationError.invalidArguments
      }
    }

    return Configuration(
      mode: mode,
      confirmedEnable: confirmed,
      logCallerText: logCallerText,
      refreshSecondsOverride: refreshOverride,
      maxStaleSeconds: maxStaleSeconds,
      identitySource: IdentitySourceConfiguration.fromEnvironment(environment)
    )
  }
}

enum ConfigurationError: Error, LocalizedError {
  case invalidArguments

  var errorDescription: String? {
    "Usage: FaceTimePicker --mode detector|answer-trusted|gatekeeper [--confirmed-enable] [--log-caller-text] [--refresh-seconds N] [--max-stale-seconds N]. Leave FACETIME_PICKER_SQLITE_PATH unset to type numbers in Terminal."
  }
}

let accessibilityTimeout: Float = 0.12
let maxCandidateAncestors = 10
let maxCandidateDepth = 10
let maxCandidateNodes = 420
let focusedPollInterval: TimeInterval = 0.10
let focusedPollRootLimit = 72
let focusedPollTimeBudgetMs = 180.0
let maxObserverRegistrationPairs = 1_200
let maxRegistrationFailureSamples = 8
let heartbeatInterval: TimeInterval = 5.0
let activeCallCheckInterval: TimeInterval = 0.10
let unverifiedIdentityGraceMs = 900.0
let recentActionCooldownMs = 1_500.0

func nowNanoseconds() -> UInt64 {
  DispatchTime.now().uptimeNanoseconds
}

func milliseconds(from start: UInt64, to end: UInt64 = nowNanoseconds()) -> Double {
  guard end >= start else { return 0 }
  return Double(end - start) / 1_000_000.0
}

func logLine(_ message: String) {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  print("[\(formatter.string(from: Date()))] \(message)")
}

func writeError(_ message: String) {
  FileHandle.standardError.write(Data((message + "\n").utf8))
}

func quoteForLog(_ value: String) -> String {
  "\""
    + value.replacingOccurrences(of: "\\", with: "\\\\")
    .replacingOccurrences(of: "\"", with: "\\\"") + "\""
}
#endif
