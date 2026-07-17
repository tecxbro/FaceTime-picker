import Foundation

@main
struct CoreLogicTests {
  static func main() throws {
    var failures = 0
    func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
      if condition() { print("PASS \(name)") } else { failures += 1; print("FAIL \(name)") }
    }

    let exampleNumber = "+1 (202) 555-0147"
    let secondNumber = "+44 20 7946 0958"
    expect(canonicalPhoneVariants(exampleNumber) == ["12025550147", "2025550147"], "US phone variants")
    expect(canonicalPhoneVariants(secondNumber).contains("442079460958"), "international phone variant")
    expect(normalizeSearchText("  Example Contact, FaceTime Video ") == "example contact facetime video", "text normalization")
    expect(isUsableAlias("Example Contact"), "valid alias")
    expect(!isUsableAlias("missing value"), "reject missing value alias")
    expect(!isUsableAlias("widgets-overlay-view"), "reject internal AX identifier alias")
    expect(looksLikeFaceTimeMarker("FaceTime Audio"), "FaceTime marker")
    expect(looksLikeAnswerLabel("Answer"), "Answer label")
    expect(looksLikeDeclineLabel("Decline"), "Decline label")

    let index = TrustedIdentityIndex(configuredNumbers: [exampleNumber, secondNumber],
      uniqueAliases: ["Example Contact"], ambiguousAliases: ["Shared Name"], matchingContactCount: 1)
    expect(index.match(texts: ["Example Contact, FaceTime Video"]).isTrusted, "unique alias match")
    expect(index.match(texts: [exampleNumber]).source == .phoneNumber, "direct number match")
    expect(index.match(texts: ["Shared Name"]).source == .ambiguousContactAlias, "ambiguous alias fail closed")
    expect(cleanedCallerText(from: ["Example Contact, FaceTime Video"], identity: index) == "Example Contact", "clean caller text")
    expect(cleanedCallerText(from: ["widgets-overlay-view", "FaceTime Video", "Answer", "Decline"], identity: index) == "unavailable", "internal identifier is not caller identity")
    expect(!looksLikeHumanCallerIdentity("widgets-overlay-view"), "internal identifier rejected")
    expect(looksLikeHumanCallerIdentity("Another Person"), "human caller accepted")

    expect(gatekeeperIdentityDecision(identityMatch: IdentityMatch(isTrusted: true, source: .uniqueContactAlias, matchedValue: nil), callerText: "Example Contact") == .answerTrusted, "trusted answer decision")
    expect(gatekeeperIdentityDecision(identityMatch: IdentityMatch(isTrusted: false, source: .none, matchedValue: nil), callerText: "Another Person") == .declineNonMatch, "explicit non-match decline decision")
    expect(gatekeeperIdentityDecision(identityMatch: IdentityMatch(isTrusted: false, source: .none, matchedValue: nil), callerText: "widgets-overlay-view") == .waitForIdentity, "internal identifier receives identity grace")

    let envelopeJSON = """
      {"schemaVersion":1,"trustedCallers":[
        {"id":"primary","phoneNumber":"+1 202 555 0147","enabled":true},
        {"id":"disabled","phoneNumber":"+1 202 555 0199","enabled":false}
      ],"cacheTTLSeconds":120}
      """.data(using: .utf8)!
    let envelopeSnapshot = try decodeTrustedCallerSnapshot(envelopeJSON)
    expect(envelopeSnapshot.phoneNumbers == ["+1 202 555 0147"], "envelope payload decoding")
    expect(envelopeSnapshot.suggestedTTLSeconds == 120, "payload TTL")

    let arrayJSON = """
      [{"id":"primary","phone_number":"+44 20 7946 0958","enabled":true}]
      """.data(using: .utf8)!
    let arraySnapshot = try decodeTrustedCallerSnapshot(arrayJSON)
    expect(arraySnapshot.phoneNumbers == ["+44 20 7946 0958"], "bare array and snake_case decoding")

    do {
      _ = try decodeTrustedCallerSnapshot(Data("{\"schemaVersion\":2,\"trustedCallers\":[{\"phoneNumber\":\"+12025550147\"}]}".utf8))
      expect(false, "unsupported schema rejected")
    } catch IdentitySourceError.unsupportedSchemaVersion(2) { expect(true, "unsupported schema rejected") }

    do {
      _ = try decodeTrustedCallerSnapshot(Data("{\"trustedCallers\":[]}".utf8))
      expect(false, "empty allowlist rejected")
    } catch IdentitySourceError.emptyAllowlist { expect(true, "empty allowlist rejected") }

    do {
      let config = try IdentitySourceConfiguration.fromEnvironment([
        "FACETIME_PICKER_IDENTITY_URL": "https://example.test/trusted-callers",
        "FACETIME_PICKER_HEADER_ENVS": "Authorization=TEST_AUTH,apikey=TEST_KEY",
        "TEST_AUTH": "Bearer runtime-secret", "TEST_KEY": "runtime-key",
      ])
      if case .https(_, let headers, _) = config {
        expect(headers["Authorization"] == "Bearer runtime-secret", "arbitrary auth header mapping")
        expect(headers["apikey"] == "runtime-key", "multiple auth headers")
      } else { expect(false, "HTTPS identity configuration") }
    } catch { expect(false, "HTTPS identity configuration") }

    do {
      _ = try IdentitySourceConfiguration.fromEnvironment(["FACETIME_PICKER_IDENTITY_URL": "http://example.test/trusted-callers"])
      expect(false, "insecure HTTP rejected")
    } catch IdentitySourceError.insecureURL { expect(true, "insecure HTTP rejected") }

    if failures > 0 { print("FAILED \(failures) test(s)"); exit(1) }
    print("ALL CORE TESTS PASSED")
  }
}
