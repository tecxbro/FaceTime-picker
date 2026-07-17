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

    let exampleNumber = "+1 (202) 555-0147"
    let secondNumber = "+44 20 7946 0958"
    expect(
      canonicalPhoneVariants(exampleNumber) == ["12025550147", "2025550147"], "US phone variants")
    expect(
      canonicalPhoneVariants(secondNumber).contains("442079460958"), "international phone variant")
    expect(
      normalizeSearchText("  Example Contact, FaceTime Video ") == "example contact facetime video",
      "text normalization")
    expect(isUsableAlias("Example Contact"), "valid alias")
    expect(!isUsableAlias("missing value"), "reject missing value alias")
    expect(!isUsableAlias("widgets-overlay-view"), "reject internal AX identifier alias")
    expect(looksLikeFaceTimeMarker("FaceTime Audio"), "FaceTime marker")
    expect(looksLikeAnswerLabel("Answer"), "Answer label")
    expect(looksLikeDeclineLabel("Decline"), "Decline label")

    let index = TrustedIdentityIndex(
      configuredNumbers: [exampleNumber, secondNumber],
      uniqueAliases: ["Example Contact"],
      ambiguousAliases: ["Shared Name"],
      matchingContactCount: 1
    )
    expect(index.match(texts: ["Example Contact, FaceTime Video"]).isTrusted, "unique alias match")
    expect(index.match(texts: [exampleNumber]).source == .phoneNumber, "direct number match")
    expect(
      index.match(texts: ["Shared Name"]).source == .ambiguousContactAlias,
      "ambiguous alias fail closed")
    expect(
      cleanedCallerText(from: ["Example Contact, FaceTime Video"], identity: index)
        == "Example Contact", "clean caller text")
    expect(
      cleanedCallerText(
        from: ["widgets-overlay-view", "FaceTime Video", "Answer", "Decline"], identity: index)
        == "unavailable", "internal identifier is not caller identity")
    expect(!looksLikeHumanCallerIdentity("widgets-overlay-view"), "internal identifier rejected")
    expect(looksLikeHumanCallerIdentity("Another Person"), "human caller accepted")

    expect(
      gatekeeperIdentityDecision(
        identityMatch: IdentityMatch(
          isTrusted: true, source: .uniqueContactAlias, matchedValue: nil),
        callerText: "Example Contact"
      ) == .answerTrusted,
      "trusted answer decision"
    )
    expect(
      gatekeeperIdentityDecision(
        identityMatch: IdentityMatch(isTrusted: false, source: .none, matchedValue: nil),
        callerText: "Another Person"
      ) == .declineNonMatch,
      "explicit non-match decline decision"
    )
    expect(
      gatekeeperIdentityDecision(
        identityMatch: IdentityMatch(isTrusted: false, source: .none, matchedValue: nil),
        callerText: "widgets-overlay-view"
      ) == .waitForIdentity,
      "internal identifier receives identity grace"
    )

    let envelopeJSON = """
      {
        "schemaVersion": 1,
        "trustedCallers": [
          {"id":"primary","phoneNumber":"+1 202 555 0147","enabled":true},
          {"id":"disabled","phoneNumber":"+1 202 555 0199","enabled":false}
        ],
        "cacheTTLSeconds": 120
      }
      """.data(using: .utf8)!
    let envelopeSnapshot = try decodeTrustedCallerSnapshot(envelopeJSON)
    expect(envelopeSnapshot.phoneNumbers == ["+1 202 555 0147"], "envelope payload decoding")
    expect(envelopeSnapshot.suggestedTTLSeconds == 120, "payload TTL")

    let arrayJSON = """
      [
        {"id":"primary","phone_number":"+44 20 7946 0958","enabled":true}
      ]
      """.data(using: .utf8)!
    let arraySnapshot = try decodeTrustedCallerSnapshot(arrayJSON)
    expect(arraySnapshot.phoneNumbers == ["+44 20 7946 0958"], "bare array and snake_case decoding")

    do {
      _ = try decodeTrustedCallerSnapshot(
        Data("{\"schemaVersion\":2,\"trustedCallers\":[{\"phoneNumber\":\"+12025550147\"}]}".utf8))
      expect(false, "unsupported schema rejected")
    } catch IdentitySourceError.unsupportedSchemaVersion(2) {
      expect(true, "unsupported schema rejected")
    }

    do {
      _ = try decodeTrustedCallerSnapshot(Data("{\"trustedCallers\":[]}".utf8))
      expect(false, "empty allowlist rejected")
    } catch IdentitySourceError.emptyAllowlist {
      expect(true, "empty allowlist rejected")
    }

    do {
      let terminal = try IdentitySourceConfiguration.fromEnvironment([:])
      expect(terminal == .terminal, "terminal source is default")
    } catch {
      expect(false, "terminal source is default")
    }

    do {
      let sqlite = try IdentitySourceConfiguration.fromEnvironment([
        "FACETIME_PICKER_SQLITE_PATH": "/tmp/trusted.sqlite3"
      ])
      if case .sqlite(let url, let table, let phoneColumn, let enabledColumn) = sqlite {
        expect(url.path == "/tmp/trusted.sqlite3", "SQLite path configuration")
        expect(table == "trusted_callers", "SQLite default table")
        expect(phoneColumn == "phone_number", "SQLite default phone column")
        expect(enabledColumn == "enabled", "SQLite default enabled column")
      } else {
        expect(false, "SQLite identity configuration")
      }
    } catch {
      expect(false, "SQLite identity configuration")
    }

    do {
      _ = try IdentitySourceConfiguration.fromEnvironment([
        "FACETIME_PICKER_SQLITE_PATH": "/tmp/trusted.sqlite3",
        "FACETIME_PICKER_IDENTITY_FILE": "/tmp/trusted.json",
      ])
      expect(false, "conflicting local sources rejected")
    } catch IdentitySourceError.conflictingSources {
      expect(true, "conflicting local sources rejected")
    }

    expect(isValidSQLiteIdentifier("trusted_callers"), "valid SQLite identifier")
    expect(!isValidSQLiteIdentifier("trusted-callers"), "invalid SQLite identifier")
    expect(!isValidSQLiteIdentifier("1trusted_callers"), "identifier cannot start with number")

    do {
      let snapshot = try validatedSnapshot(
        phoneNumbers: ["+1 (202) 555-0147", "+1 202 555 0147"],
        suggestedTTLSeconds: 30
      )
      expect(snapshot.phoneNumbers.count == 1, "duplicate numbers deduplicated")
    } catch {
      expect(false, "duplicate numbers deduplicated")
    }

    #if os(macOS)
      do {
        let databaseURL = FileManager.default.temporaryDirectory
          .appendingPathComponent("FaceTimePickerLocalTests-\(UUID().uuidString).sqlite3")
        var database: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK, let database else {
          expect(false, "SQLite fixture opens")
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

        let source = ConfiguredTrustedCallerSource(
          configuration: .sqlite(
            url: databaseURL,
            table: "trusted_callers",
            phoneColumn: "phone_number",
            enabledColumn: "enabled"
          )
        )
        let snapshot = try source.load()
        expect(snapshot.phoneNumbers == ["+1 202 555 0147"], "SQLite enabled rows only")
        try? FileManager.default.removeItem(at: databaseURL)
      } catch {
        expect(false, "SQLite enabled rows only")
      }
    #endif

    if failures > 0 {
      print("FAILED \(failures) test(s)")
      exit(1)
    }
    print("ALL CORE TESTS PASSED")
  }
}
