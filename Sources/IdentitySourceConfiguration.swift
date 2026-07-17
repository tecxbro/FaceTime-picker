import Foundation

enum IdentitySourceConfiguration: Equatable, Sendable {
  case terminal
  case sqlite(
    url: URL,
    table: String,
    phoneColumn: String,
    enabledColumn: String
  )
  case jsonFile(url: URL)

  static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment)
    throws -> IdentitySourceConfiguration
  {
    let rawSQLite = environment["FACETIME_PICKER_SQLITE_PATH"]?.trimmingCharacters(
      in: .whitespacesAndNewlines)
    let rawFile = environment["FACETIME_PICKER_IDENTITY_FILE"]?.trimmingCharacters(
      in: .whitespacesAndNewlines)

    let hasSQLite = !(rawSQLite ?? "").isEmpty
    let hasFile = !(rawFile ?? "").isEmpty
    guard !(hasSQLite && hasFile) else { throw IdentitySourceError.conflictingSources }

    if let rawSQLite, hasSQLite {
      let table = environment["FACETIME_PICKER_SQLITE_TABLE"] ?? "trusted_callers"
      let phoneColumn = environment["FACETIME_PICKER_SQLITE_PHONE_COLUMN"] ?? "phone_number"
      let enabledColumn = environment["FACETIME_PICKER_SQLITE_ENABLED_COLUMN"] ?? "enabled"
      guard isValidSQLiteIdentifier(table), isValidSQLiteIdentifier(phoneColumn),
        isValidSQLiteIdentifier(enabledColumn)
      else {
        throw IdentitySourceError.invalidSQLiteIdentifier
      }
      let expanded = NSString(string: rawSQLite).expandingTildeInPath
      return .sqlite(
        url: URL(fileURLWithPath: expanded),
        table: table,
        phoneColumn: phoneColumn,
        enabledColumn: enabledColumn
      )
    }

    if let rawFile, hasFile {
      let expanded = NSString(string: rawFile).expandingTildeInPath
      return .jsonFile(url: URL(fileURLWithPath: expanded))
    }

    return .terminal
  }

  var sourceKind: String {
    switch self {
    case .terminal: return "terminal"
    case .sqlite: return "sqlite"
    case .jsonFile: return "jsonFile"
    }
  }

  var supportsRefresh: Bool {
    switch self {
    case .terminal: return false
    case .sqlite, .jsonFile: return true
    }
  }
}

func isValidSQLiteIdentifier(_ value: String) -> Bool {
  guard let first = value.unicodeScalars.first else { return false }
  let firstAllowed = CharacterSet.letters.union(CharacterSet(charactersIn: "_"))
  let remainingAllowed = firstAllowed.union(.decimalDigits)
  guard firstAllowed.contains(first) else { return false }
  return value.unicodeScalars.dropFirst().allSatisfy { remainingAllowed.contains($0) }
}
