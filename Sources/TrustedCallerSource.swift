import Foundation

#if os(macOS)
  import SQLite3
#endif

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
    case .jsonFile(let url):
      guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
        throw IdentitySourceError.fileReadFailed
      }
      return try decodeTrustedCallerSnapshot(data)
    case .sqlite(let url, let table, let phoneColumn, let enabledColumn):
      return try loadFromSQLite(
        url: url,
        table: table,
        phoneColumn: phoneColumn,
        enabledColumn: enabledColumn
      )
    }
  }

  private func loadFromTerminalOnce() throws -> TrustedCallerSnapshot {
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

  private func loadFromSQLite(
    url: URL,
    table: String,
    phoneColumn: String,
    enabledColumn: String
  ) throws -> TrustedCallerSnapshot {
    #if os(macOS)
      var database: OpaquePointer?
      let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
      guard sqlite3_open_v2(url.path, &database, flags, nil) == SQLITE_OK, let database else {
        if let database { sqlite3_close(database) }
        throw IdentitySourceError.sqliteOpenFailed
      }
      defer { sqlite3_close(database) }
      sqlite3_busy_timeout(database, 750)

      let query =
        "SELECT \"\(phoneColumn)\" FROM \"\(table)\" WHERE \"\(enabledColumn)\" = 1"
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

func decodeTrustedCallerSnapshot(_ data: Data) throws -> TrustedCallerSnapshot {
  guard data.count <= 256 * 1024 else { throw IdentitySourceError.responseTooLarge }
  let decoder = JSONDecoder()

  let envelope: TrustedCallerEnvelope
  if let decoded = try? decoder.decode(TrustedCallerEnvelope.self, from: data) {
    envelope = decoded
  } else if let records = try? decoder.decode([TrustedCallerRecord].self, from: data) {
    envelope = TrustedCallerEnvelope(trustedCallers: records)
  } else {
    throw IdentitySourceError.invalidPayload
  }

  guard envelope.schemaVersion == 1 else {
    throw IdentitySourceError.unsupportedSchemaVersion(envelope.schemaVersion)
  }
  let enabledNumbers = envelope.trustedCallers.filter(\.enabled).map(\.phoneNumber)
  return try validatedSnapshot(
    phoneNumbers: enabledNumbers,
    suggestedTTLSeconds: envelope.cacheTTLSeconds
  )
}

func validatedSnapshot(phoneNumbers: [String], suggestedTTLSeconds: Int?) throws
  -> TrustedCallerSnapshot
{
  var seen = Set<String>()
  var validated: [String] = []
  for number in phoneNumbers {
    let trimmed = number.trimmingCharacters(in: .whitespacesAndNewlines)
    let digits = digitsOnly(trimmed)
    guard (7...15).contains(digits.count) else { throw IdentitySourceError.invalidPhoneNumber }
    guard seen.insert(digits).inserted else { continue }
    validated.append(trimmed)
  }
  guard !validated.isEmpty else { throw IdentitySourceError.emptyAllowlist }
  let ttl = suggestedTTLSeconds.map { max(5, min($0, 86_400)) }
  return TrustedCallerSnapshot(phoneNumbers: validated, suggestedTTLSeconds: ttl)
}
