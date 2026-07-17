import Foundation

#if os(macOS)
  import SQLite3
#endif

@main
struct CoreLogicTests {
  static func main() throws {
    var failures = 0

    func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
      if condition() {
        print("PASS \(name)")
      } else {
        failures += 1
        print("FAIL \(name)")
      }
    }

    let firstNumber = "+1 (202) 555-0147"
    let secondNumber = "+44 20 7946 0958"
    expect(canonicalPhoneVariants(firstNumber) == ["12025550147", "2025550147"], "US phone variants")
    expect(canonicalPhoneVariants(secondNumber).contains("442079460958"), "international phone variant")
    expect(normalizeSearchText("  Example Contact, FaceTime Video ") == "example contact facetime video", "text normalization")
    expect(isUsableAlias("Example Contact"), "valid alias")
    expect(!isUsableAlias("widgets-overlay-view"), "reject internal AX identifier alias")

    let index = TrustedIdentityIndex(
      configuredNumbers: [firstNumber, secondNumber],
      uniqueAliases: ["Example Contact"],
      ambiguousAliases: ["Shared Name"],
      matchingContactCount: 1
    )
    expect(index.match(texts: ["Example Contact, FaceTime Video"]).isTrusted, "unique alias match")
    expect(index.match(texts: [firstNumber]).source == .phoneNumber, "direct number match")
    expect(index.match(texts: ["Shared Name"]).source == .ambiguousContactAlias, "ambiguous alias fails closed")
    expect(
      cleanedCallerText(
        from: ["widgets-overlay-view", "FaceTime Video", "Answer", "Decline"],
        identity: index
      ) == "unavailable",
      "internal identifier is not caller identity"
    )
    expect(
      gatekeeperIdentityDecision(
        identityMatch: IdentityMatch(isTrusted: true, source: .uniqueContactAlias, matchedValue: nil),
        callerText: "Example Contact"
      ) == .answerTrusted,
      "trusted caller is answered"
    )
    expect(
      gatekeeperIdentityDecision(
        identityMatch: IdentityMatch(isTrusted: false, source: .none, matchedValue: nil),
        callerText: "Another Person"
      ) == .declineNonMatch,
      "explicit non-match is declined"
    )
    expect(
      gatekeeperIdentityDecision(
        identityMatch: IdentityMatch(isTrusted: false, source: .none, matchedValue: nil),
        callerText: "widgets-overlay-view"
      ) == .waitForIdentity,
      "internal identifier receives identity grace"
    )

    expect(IdentitySourceConfiguration.fromEnvironment([:]) == .terminal, "Terminal source is default")
    let sqliteConfig = IdentitySourceConfiguration.fromEnvironment([
      "FACETIME_PICKER_SQLITE_PATH": "~/trusted.sqlite3"
    ])
    if case .sqlite(let url) = sqliteConfig {
      expect(url.path.hasSuffix("/trusted.sqlite3"), "SQLite path configuration")
    } else {
      expect(false, "SQLite path configuration")
    }

    let snapshot = try validatedSnapshot(
      phoneNumbers: [firstNumber, "+1 202 555 0147"],
      suggestedTTLSeconds: 30
    )
    expect(snapshot.phoneNumbers.count == 1, "duplicate numbers are deduplicated")
    expect(snapshot.suggestedTTLSeconds == 30, "refresh interval is retained")

    do {
      _ = try validatedSnapshot(phoneNumbers: ["123"], suggestedTTLSeconds: nil)
      expect(false, "short phone number is rejected")
    } catch IdentitySourceError.invalidPhoneNumber {
      expect(true, "short phone number is rejected")
    }

    #if os(macOS)
      do {
        let databaseURL = FileManager.default.temporaryDirectory
          .appendingPathComponent("FaceTimePickerTests-\(UUID().uuidString).sqlite3")
        var database: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK, let database else {
          throw IdentitySourceError.sqliteOpenFailed
        }
        let fixtureSQL = """
          CREATE TABLE trusted_callers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            phone_number TEXT NOT NULL UNIQUE,
            enabled INTEGER NOT NULL DEFAULT 1
          );
          INSERT INTO trusted_callers (phone_number, enabled) VALUES ('+1 202 555 0147', 1);
          INSERT INTO trusted_callers (phone_number, enabled) VALUES ('+1 202 555 0199', 0);
          """
        let fixtureResult = sqlite3_exec(database, fixtureSQL, nil, nil, nil)
        sqlite3_close(database)
        expect(fixtureResult == SQLITE_OK, "SQLite fixture schema")

        let source = ConfiguredTrustedCallerSource(configuration: .sqlite(url: databaseURL))
        let loaded = try source.load()
        expect(loaded.phoneNumbers == ["+1 202 555 0147"], "SQLite loads enabled rows only")
        try? FileManager.default.removeItem(at: databaseURL)
      } catch {
        expect(false, "SQLite loads enabled rows only")
      }
    #endif

    if failures > 0 {
      print("FAILED \(failures) test(s)")
      exit(1)
    }
    print("ALL CORE TESTS PASSED")
  }
}
