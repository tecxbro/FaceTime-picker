import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

protocol TrustedCallerSource: Sendable {
  func load() throws -> TrustedCallerSnapshot
}

struct ConfiguredTrustedCallerSource: TrustedCallerSource {
  let configuration: IdentitySourceConfiguration

  func load() throws -> TrustedCallerSnapshot {
    let data: Data
    switch configuration {
    case .jsonFile(let url):
      guard let loaded = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
        throw IdentitySourceError.fileReadFailed
      }
      data = loaded
    case .https(let url, let headers, let timeoutSeconds):
      data = try fetch(url: url, headers: headers, timeoutSeconds: timeoutSeconds)
    }
    return try decodeTrustedCallerSnapshot(data)
  }

  private func fetch(url: URL, headers: [String: String], timeoutSeconds: Double) throws -> Data {
    var request = URLRequest(
      url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeoutSeconds
    )
    request.httpMethod = "GET"
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    for (name, value) in headers {
      request.setValue(value, forHTTPHeaderField: name)
    }

    // Startup and refresh run synchronously from the coordinator's worker path.
    // The locked result box keeps URLSession callback data Swift 6 concurrency-safe.
    let result = SynchronousURLResult()
    let semaphore = DispatchSemaphore(value: 0)
    let task = URLSession.shared.dataTask(with: request) { data, response, error in
      result.set(data: data, response: response, error: error)
      semaphore.signal()
    }
    task.resume()
    guard semaphore.wait(timeout: .now() + timeoutSeconds + 1) == .success else {
      task.cancel()
      throw IdentitySourceError.requestTimedOut
    }
    let snapshot = result.read()
    if snapshot.error != nil { throw IdentitySourceError.transportFailure }
    guard let response = snapshot.response as? HTTPURLResponse else {
      throw IdentitySourceError.transportFailure
    }
    guard response.statusCode == 200 else {
      throw IdentitySourceError.invalidHTTPStatus(response.statusCode)
    }
    guard let data = snapshot.data else { throw IdentitySourceError.invalidPayload }
    return data
  }
}

private final class SynchronousURLResult: @unchecked Sendable {
  private let lock = NSLock()
  private var data: Data?
  private var response: URLResponse?
  private var error: Error?

  func set(data: Data?, response: URLResponse?, error: Error?) {
    lock.lock()
    self.data = data
    self.response = response
    self.error = error
    lock.unlock()
  }

  func read() -> (data: Data?, response: URLResponse?, error: Error?) {
    lock.lock()
    defer { lock.unlock() }
    return (data, response, error)
  }
}

func decodeTrustedCallerSnapshot(_ data: Data) throws -> TrustedCallerSnapshot {
  // Bound the response before decoding so a misconfigured endpoint cannot make
  // the desktop process allocate an unexpectedly large JSON object.
  guard data.count <= 256 * 1024 else { throw IdentitySourceError.responseTooLarge }
  let decoder = JSONDecoder()

  // The envelope is canonical; the bare array remains a compatibility format.
  let envelope: TrustedCallerEnvelope
  if let decoded = try? decoder.decode(TrustedCallerEnvelope.self, from: data) {
    envelope = decoded
  } else if let callers = try? decoder.decode([TrustedCallerRecord].self, from: data) {
    envelope = TrustedCallerEnvelope(trustedCallers: callers)
  } else {
    throw IdentitySourceError.invalidPayload
  }

  guard envelope.schemaVersion == 1 else {
    throw IdentitySourceError.unsupportedSchemaVersion(envelope.schemaVersion)
  }

  var normalizedNumbers: [String] = []
  var seen: Set<String> = []
  for record in envelope.trustedCallers where record.enabled {
    let digits = digitsOnly(record.phoneNumber)
    guard digits.count >= 7, digits.count <= 15 else {
      throw IdentitySourceError.invalidPhoneNumber
    }
    if seen.insert(digits).inserted {
      normalizedNumbers.append(record.phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines))
    }
  }

  // Rejecting an empty snapshot distinguishes provider failure from an explicit
  // working allowlist. Refresh logic keeps the previous snapshot until it expires.
  guard !normalizedNumbers.isEmpty else { throw IdentitySourceError.emptyAllowlist }

  let ttl = envelope.cacheTTLSeconds.map { max(30, min($0, 86_400)) }
  return TrustedCallerSnapshot(phoneNumbers: normalizedNumbers, suggestedTTLSeconds: ttl)
}
