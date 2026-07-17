import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

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
          codingPath: decoder.codingPath, debugDescription: "Expected phoneNumber or phone_number")
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
  case missingSource
  case conflictingSources
  case invalidURL
  case insecureURL
  case invalidHeaderEnvironment(String)
  case missingHeaderEnvironment(String)
  case invalidHeaderValue(String)
  case fileReadFailed
  case responseTooLarge
  case invalidHTTPStatus(Int)
  case invalidPayload
  case unsupportedSchemaVersion(Int)
  case invalidPhoneNumber
  case emptyAllowlist
  case requestTimedOut
  case transportFailure

  var errorDescription: String? {
    switch self {
    case .missingSource:
      return "Configure FACETIME_PICKER_IDENTITY_URL or FACETIME_PICKER_IDENTITY_FILE."
    case .conflictingSources:
      return "Configure exactly one identity source: URL or file, not both."
    case .invalidURL:
      return "The configured identity URL is invalid."
    case .insecureURL:
      return "The identity URL must use HTTPS. Use a local JSON file for offline development."
    case .invalidHeaderEnvironment(let value):
      return "Invalid header mapping: \(value). Expected Header-Name=ENVIRONMENT_VARIABLE."
    case .missingHeaderEnvironment(let name):
      return "The required header environment variable \(name) is not set."
    case .invalidHeaderValue(let name):
      return "The header value loaded from \(name) is invalid."
    case .fileReadFailed:
      return "The identity JSON file could not be read."
    case .responseTooLarge:
      return "The identity response exceeded the 256 KB safety limit."
    case .invalidHTTPStatus(let status):
      return "The identity endpoint returned HTTP \(status)."
    case .invalidPayload:
      return "The identity response did not match the documented JSON contract."
    case .unsupportedSchemaVersion(let version):
      return "Unsupported identity schema version \(version)."
    case .invalidPhoneNumber:
      return "The identity response contained an invalid phone number."
    case .emptyAllowlist:
      return "The identity response contained no enabled trusted callers."
    case .requestTimedOut:
      return "The identity endpoint request timed out."
    case .transportFailure:
      return "The identity endpoint request failed."
    }
  }
}
