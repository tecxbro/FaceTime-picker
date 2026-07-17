import Foundation

#if os(macOS)
  import SQLite3
#endif

struct TrustedCallerSnapshot: Equatable, Sendable {
  let phoneNumbers: [String]
  let suggestedTTLSeconds: Int?
}

enum IdentitySourceError: Error, LocalizedError, Equatable {
  case terminalInputUnavailable
  case invalidPhoneNumber
  case emptyAllowlist
  case sqliteOpenFailed
  case sqliteQueryFailed
  case sqliteUnavailable

  var errorDescription: String? {
    switch self {
    case .terminalInputUnavailable:
      return "Trusted phone numbers could not be read from Terminal."
    case .invalidPhoneNumber:
      return "A trusted phone number must contain 7 to 15 digits."
    case .emptyAllowlist:
      return "No enabled trusted callers were provided."
    case .sqliteOpenFailed:
      return "The local SQLite database could not be opened read-only."
    case .sqliteQueryFailed:
      return "The SQLite query failed. Expected trusted_callers(phone_number, enabled)."
    case .sqliteUnavailable:
      return "SQLite identity sources are supported only on macOS."
    }
  }
}

protocol TrustedCallerSource: Sendable {
  func load() throws -> TrustedCallerSnapshot
}

final class ConfiguredTrustedCallerSource: TrustedCallerSource, @unchecked Sendable {
  let configuration: IdentitySourceConfiguration
  private let lock = NSLock()
  private var terminalSnapshot: TrustedCallerSnapshot?

  init(configuration: IdentitySourceConfiguration) {
    self.configuration = configuration
  }

  func load() throws -> TrustedCallerSnapshot {
    switch configuration {
    case .terminal:
      return try loadFromTerminalOnce()
    case .sqlite(let url):
      return try loadFromSQLite(url: url)
    }
  }

  private func loadFromTerminalOnce() throws -> TrustedCallerSnapshot {
    // Keep the prompt result in memory so no later code path can unexpectedly prompt again.
    lock.lock()
    if let terminalSnapshot {
      lock.unlock()
      return terminalSnapshot
    }
    lock.unlock()

    print("Enter trusted phone number(s), separated by commas:")
    guard let line = readLine() else { throw IdentitySourceError.terminalInputUnavailable }
    let values = line
      .split(separator: ",", omittingEmptySubsequences: true)
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    let snapshot = try validatedSnapshot(phoneNumbers: values, suggestedTTLSeconds: nil)
    lock.lock()
    terminalSnapshot = snapshot
    lock.unlock()
    return snapshot
  }

  private func loadFromSQLite(url: URL) throws -> TrustedCallerSnapshot {
    #if os(macOS)
      var database: OpaquePointer?
      // The Swift process never writes to the user's allowlist. run.sh owns optional setup changes.
      let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
      guard sqlite3_open_v2(url.path, &database, flags, nil) == SQLITE_OK, let database else {
        if let database { sqlite3_close(database) }
        throw IdentitySourceError.sqliteOpenFailed
      }
      defer { sqlite3_close(database) }
      sqlite3_busy_timeout(database, 750)

      // A fixed schema keeps the query reviewable and avoids interpolating table or column names.
      let query = "SELECT phone_number FROM trusted_callers WHERE enabled = 1"
      var statement: OpaquePointer?
      guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
        let statement
      else {
        throw IdentitySourceError.sqliteQueryFailed
      }
      defer { sqlite3_finalize(statement) }

      var phoneNumbers: [String] = []
      while true {
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { break }
        guard result == SQLITE_ROW else { throw IdentitySourceError.sqliteQueryFailed }
        guard let raw = sqlite3_column_text(statement, 0) else { continue }
        phoneNumbers.append(String(cString: raw))
      }
      return try validatedSnapshot(phoneNumbers: phoneNumbers, suggestedTTLSeconds: 30)
    #else
      throw IdentitySourceError.sqliteUnavailable
    #endif
  }
}

func validatedSnapshot(
  phoneNumbers: [String],
  suggestedTTLSeconds: Int?
) throws -> TrustedCallerSnapshot {
  var seen = Set<String>()
  var validated: [String] = []

  for number in phoneNumbers {
    let trimmed = number.trimmingCharacters(in: .whitespacesAndNewlines)
    let digits = digitsOnly(trimmed)
    guard (7...15).contains(digits.count) else { throw IdentitySourceError.invalidPhoneNumber }
    // Compare canonical digits so differently formatted copies of one number do not create duplicates.
    guard seen.insert(digits).inserted else { continue }
    validated.append(trimmed)
  }

  guard !validated.isEmpty else { throw IdentitySourceError.emptyAllowlist }
  let ttl = suggestedTTLSeconds.map { max(5, min($0, 86_400)) }
  return TrustedCallerSnapshot(phoneNumbers: validated, suggestedTTLSeconds: ttl)
}
