import Foundation

struct TrustedCallerRecord: Codable, Equatable, Sendable {
  let id: String?
  let phoneNumber: String
  let enabled: Bool

  init(id: String? = nil, phoneNumber: String, enabled: Bool = true) {
    self.id = id
    self.phoneNumber = phoneNumber
    self.enabled = enabled
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case phoneNumber
    case phoneNumberSnake = "phone_number"
    case enabled
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(String.self, forKey: .id)
    if let camel = try container.decodeIfPresent(String.self, forKey: .phoneNumber) {
      phoneNumber = camel
    } else if let snake = try container.decodeIfPresent(String.self, forKey: .phoneNumberSnake) {
      phoneNumber = snake
    } else {
      throw DecodingError.keyNotFound(
        CodingKeys.phoneNumber,
        DecodingError.Context(
          codingPath: decoder.codingPath,
          debugDescription: "Expected phoneNumber or phone_number"
        )
      )
    }
    enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(id, forKey: .id)
    try container.encode(phoneNumber, forKey: .phoneNumber)
    try container.encode(enabled, forKey: .enabled)
  }
}

struct TrustedCallerEnvelope: Codable, Equatable, Sendable {
  let schemaVersion: Int
  let trustedCallers: [TrustedCallerRecord]
  let cacheTTLSeconds: Int?

  init(schemaVersion: Int = 1, trustedCallers: [TrustedCallerRecord], cacheTTLSeconds: Int? = nil) {
    self.schemaVersion = schemaVersion
    self.trustedCallers = trustedCallers
    self.cacheTTLSeconds = cacheTTLSeconds
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion
    case schemaVersionSnake = "schema_version"
    case trustedCallers
    case trustedCallersSnake = "trusted_callers"
    case cacheTTLSeconds
    case cacheTTLSecondsSnake = "cache_ttl_seconds"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion =
      try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
      ?? container.decodeIfPresent(Int.self, forKey: .schemaVersionSnake)
      ?? 1
    trustedCallers =
      try container.decodeIfPresent([TrustedCallerRecord].self, forKey: .trustedCallers)
      ?? container.decodeIfPresent([TrustedCallerRecord].self, forKey: .trustedCallersSnake)
      ?? []
    cacheTTLSeconds =
      try container.decodeIfPresent(Int.self, forKey: .cacheTTLSeconds)
      ?? container.decodeIfPresent(Int.self, forKey: .cacheTTLSecondsSnake)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(schemaVersion, forKey: .schemaVersion)
    try container.encode(trustedCallers, forKey: .trustedCallers)
    try container.encodeIfPresent(cacheTTLSeconds, forKey: .cacheTTLSeconds)
  }
}

struct TrustedCallerSnapshot: Equatable, Sendable {
  let phoneNumbers: [String]
  let suggestedTTLSeconds: Int?
}

enum IdentitySourceError: Error, LocalizedError, Equatable {
  case conflictingSources
  case invalidSQLiteIdentifier
  case terminalInputUnavailable
  case fileReadFailed
  case responseTooLarge
  case invalidPayload
  case unsupportedSchemaVersion(Int)
  case invalidPhoneNumber
  case emptyAllowlist
  case sqliteOpenFailed
  case sqliteQueryFailed
  case sqliteUnavailable

  var errorDescription: String? {
    switch self {
    case .conflictingSources:
      return "Configure either FACETIME_PICKER_SQLITE_PATH or FACETIME_PICKER_IDENTITY_FILE, not both. Leave both unset to type numbers in Terminal."
    case .invalidSQLiteIdentifier:
      return "SQLite table and column names may contain only letters, numbers, and underscores and may not begin with a number."
    case .terminalInputUnavailable:
      return "Trusted phone numbers could not be read from Terminal."
    case .fileReadFailed:
      return "The local identity JSON file could not be read."
    case .responseTooLarge:
      return "The local identity JSON exceeded the 256 KB safety limit."
    case .invalidPayload:
      return "The local identity JSON did not match the documented schema."
    case .unsupportedSchemaVersion(let version):
      return "Unsupported identity schema version \(version)."
    case .invalidPhoneNumber:
      return "A trusted phone number must contain 7 to 15 digits."
    case .emptyAllowlist:
      return "No enabled trusted callers were provided."
    case .sqliteOpenFailed:
      return "The local SQLite database could not be opened read-only."
    case .sqliteQueryFailed:
      return "The local SQLite trusted-caller query failed. Check the documented schema."
    case .sqliteUnavailable:
      return "SQLite identity sources are supported only on macOS."
    }
  }
}
