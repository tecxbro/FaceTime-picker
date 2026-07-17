import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

enum IdentitySourceConfiguration: Equatable, Sendable {
  case https(url: URL, headers: [String: String], timeoutSeconds: Double)
  case jsonFile(url: URL)

  static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment)
    throws -> IdentitySourceConfiguration
  {
    let rawURL = environment["FACETIME_PICKER_IDENTITY_URL"]?.trimmingCharacters(
      in: .whitespacesAndNewlines)
    let rawFile = environment["FACETIME_PICKER_IDENTITY_FILE"]?.trimmingCharacters(
      in: .whitespacesAndNewlines)

    let hasURL = !(rawURL ?? "").isEmpty
    let hasFile = !(rawFile ?? "").isEmpty
    guard hasURL || hasFile else { throw IdentitySourceError.missingSource }
    guard !(hasURL && hasFile) else { throw IdentitySourceError.conflictingSources }

    if let rawURL, hasURL {
      guard let url = URL(string: rawURL), url.host != nil else {
        throw IdentitySourceError.invalidURL
      }
      guard url.scheme?.lowercased() == "https" else { throw IdentitySourceError.insecureURL }

      let timeout = max(
        1, min(Double(environment["FACETIME_PICKER_REQUEST_TIMEOUT_SECONDS"] ?? "8") ?? 8, 30))
      let headerMappings = environment["FACETIME_PICKER_HEADER_ENVS"] ?? ""
      var headers: [String: String] = [:]
      for item in headerMappings.split(separator: ",", omittingEmptySubsequences: true) {
        let mapping = String(item).trimmingCharacters(in: .whitespacesAndNewlines)
        let pieces = mapping.split(separator: "=", maxSplits: 1).map(String.init)
        guard pieces.count == 2 else { throw IdentitySourceError.invalidHeaderEnvironment(mapping) }
        let header = pieces[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let environmentName = pieces[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidHTTPHeaderName(header), !environmentName.isEmpty else {
          throw IdentitySourceError.invalidHeaderEnvironment(mapping)
        }
        guard let value = environment[environmentName], !value.isEmpty else {
          throw IdentitySourceError.missingHeaderEnvironment(environmentName)
        }
        guard !value.contains("\r"), !value.contains("\n") else {
          throw IdentitySourceError.invalidHeaderValue(environmentName)
        }
        headers[header] = value
      }
      return .https(url: url, headers: headers, timeoutSeconds: timeout)
    }

    guard let rawFile, hasFile else { throw IdentitySourceError.missingSource }
    let expanded = NSString(string: rawFile).expandingTildeInPath
    return .jsonFile(url: URL(fileURLWithPath: expanded))
  }

  var sourceKind: String {
    switch self {
    case .https: return "https"
    case .jsonFile: return "jsonFile"
    }
  }
}

func isValidHTTPHeaderName(_ name: String) -> Bool {
  guard !name.isEmpty else { return false }
  let allowed = CharacterSet(
    charactersIn: "!#$%&'*+-.^_`|~0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
  return name.unicodeScalars.allSatisfy { allowed.contains($0) }
}
