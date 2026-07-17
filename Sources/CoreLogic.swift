import Foundation

struct TrustedIdentityIndex: Sendable {
  let configuredNumbers: [String]
  let digitVariants: Set<String>
  let uniqueAliases: Set<String>
  let ambiguousAliases: Set<String>
  let matchingContactCount: Int

  init(
    configuredNumbers: [String],
    uniqueAliases: Set<String> = [],
    ambiguousAliases: Set<String> = [],
    matchingContactCount: Int = 0
  ) {
    self.configuredNumbers = configuredNumbers
    self.digitVariants = Set(configuredNumbers.flatMap { canonicalPhoneVariants($0) })
    self.uniqueAliases = Set(uniqueAliases.map(normalizeSearchText).filter(isUsableAlias))
    self.ambiguousAliases = Set(ambiguousAliases.map(normalizeSearchText).filter(isUsableAlias))
    self.matchingContactCount = matchingContactCount
  }

  static let empty = TrustedIdentityIndex(configuredNumbers: [])

  func match(texts: [String]) -> IdentityMatch {
    // Prefer raw-number evidence because it does not depend on Contacts display names.
    for text in texts {
      let digits = digitsOnly(text)
      if digitVariants.contains(where: { variant in
        digits == variant || (!variant.isEmpty && digits.contains(variant))
      }) {
        return IdentityMatch(isTrusted: true, source: .phoneNumber, matchedValue: nil)
      }
    }

    // A saved name is trusted only after ContactsResolver proves that one local
    // contact—and no other contact—owns the normalized alias.
    for text in texts {
      let normalized = normalizeSearchText(text)
      if uniqueAliases.contains(where: { containsNormalizedPhrase(normalized, phrase: $0) }) {
        return IdentityMatch(isTrusted: true, source: .uniqueContactAlias, matchedValue: nil)
      }
    }

    // Preserve ambiguous aliases as an explicit non-match instead of silently
    // treating them as missing identity. Gatekeeper mode declines this state.
    for text in texts {
      let normalized = normalizeSearchText(text)
      if ambiguousAliases.contains(where: { containsNormalizedPhrase(normalized, phrase: $0) }) {
        return IdentityMatch(isTrusted: false, source: .ambiguousContactAlias, matchedValue: nil)
      }
    }

    return IdentityMatch(isTrusted: false, source: .none, matchedValue: nil)
  }
}

enum IdentityMatchSource: String, Sendable {
  case phoneNumber
  case uniqueContactAlias
  case ambiguousContactAlias
  case none
}

struct IdentityMatch: Sendable {
  let isTrusted: Bool
  let source: IdentityMatchSource
  let matchedValue: String?
}

func digitsOnly(_ input: String) -> String {
  String(
    input.unicodeScalars.compactMap { scalar in
      CharacterSet.decimalDigits.contains(scalar) ? Character(String(scalar)) : nil
    })
}

func canonicalPhoneVariants(_ input: String) -> Set<String> {
  let digits = digitsOnly(input)
  guard !digits.isEmpty else { return [] }

  // FaceTime may display a US number with or without the leading country code.
  // Keep the full international form and only add the US-compatible variants.
  var result: Set<String> = [digits]
  if digits.count >= 10 {
    result.insert(String(digits.suffix(10)))
  }
  if digits.count == 10 {
    result.insert("1" + digits)
  }
  return result
}

func normalizeSearchText(_ input: String) -> String {
  var scalars = String.UnicodeScalarView()
  for scalar in input.unicodeScalars {
    switch scalar.value {
    // Accessibility text can contain invisible bidi controls. Removing them
    // prevents visually identical caller labels from normalizing differently.
    case 0x200E, 0x200F, 0x202A...0x202E, 0x2066...0x2069:
      continue
    default:
      scalars.append(scalar)
    }
  }

  let folded = String(scalars)
    .folding(
      options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")
    )
    .lowercased()

  var output = ""
  var previousWasSpace = true
  for scalar in folded.unicodeScalars {
    if CharacterSet.alphanumerics.contains(scalar) {
      output.unicodeScalars.append(scalar)
      previousWasSpace = false
    } else if !previousWasSpace {
      output.append(" ")
      previousWasSpace = true
    }
  }
  return output.trimmingCharacters(in: .whitespacesAndNewlines)
}

func isUsableAlias(_ alias: String) -> Bool {
  let normalized = normalizeSearchText(alias)
  guard !normalized.isEmpty else { return false }
  guard !genericOrInternalIdentityLabels.contains(normalized) else { return false }
  guard normalized != "missing value", normalized != "unknown" else { return false }
  return normalized.rangeOfCharacter(from: .letters) != nil
}

func containsNormalizedPhrase(_ normalizedHaystack: String, phrase normalizedNeedle: String) -> Bool
{
  guard !normalizedNeedle.isEmpty else { return false }
  // Padding with spaces prevents an alias such as "ann" from matching "joanne".
  let paddedHaystack = " " + normalizedHaystack + " "
  let paddedNeedle = " " + normalizedNeedle + " "
  return paddedHaystack.contains(paddedNeedle)
}

func looksLikeFaceTimeMarker(_ text: String) -> Bool {
  let value = normalizeSearchText(text)
  guard containsNormalizedPhrase(value, phrase: "facetime") else { return false }
  return containsNormalizedPhrase(value, phrase: "facetime video")
    || containsNormalizedPhrase(value, phrase: "facetime audio")
    || containsNormalizedPhrase(value, phrase: "facetime call") || value == "facetime"
}

func looksLikeAnswerLabel(_ text: String) -> Bool {
  let value = normalizeSearchText(text)
  guard !value.isEmpty else { return false }
  let accepted = [
    "answer", "accept", "answer call", "accept call",
    "answer video", "accept video", "answer audio", "accept audio",
  ]
  if accepted.contains(value) { return true }
  return value.hasPrefix("answer ") || value.hasPrefix("accept ") || value.hasSuffix(" answer")
    || value.hasSuffix(" accept")
}

func looksLikeDeclineLabel(_ text: String) -> Bool {
  let value = normalizeSearchText(text)
  guard !value.isEmpty else { return false }
  let accepted = [
    "decline", "reject", "decline call", "reject call",
    "decline video", "reject video", "decline audio", "reject audio",
  ]
  if accepted.contains(value) { return true }
  return value.hasPrefix("decline ") || value.hasPrefix("reject ") || value.hasSuffix(" decline")
    || value.hasSuffix(" reject")
}

func looksLikeHangUpLabel(_ text: String) -> Bool {
  let value = normalizeSearchText(text)
  return value == "hang up" || value == "end call"
}

private let genericOrInternalIdentityLabels: Set<String> = [
  "notification center", "notification center application",
  "notification center system dialog", "system dialog",
  "facetime", "facetime video", "facetime audio", "facetime call",
  "widgets overlay view", "widget overlay view", "overlay view",
  "axapplication", "axwindow", "axgroup", "axbutton", "axstatictext",
  "answer", "accept", "decline", "reject", "hang up", "end call",
]

func looksLikeHumanCallerIdentity(_ input: String) -> Bool {
  let normalized = normalizeSearchText(removeFaceTimeWords(input))
  guard !normalized.isEmpty else { return false }
  guard !genericOrInternalIdentityLabels.contains(normalized) else { return false }
  guard !normalized.hasPrefix("ax") else { return false }
  guard !normalized.contains("widgets overlay") else { return false }
  guard !looksLikeAnswerLabel(normalized), !looksLikeDeclineLabel(normalized),
    !looksLikeHangUpLabel(normalized)
  else {
    return false
  }
  let digits = digitsOnly(normalized)
  if digits.count >= 7 { return true }
  return normalized.rangeOfCharacter(from: .letters) != nil
}

func cleanedCallerText(from texts: [String], identity: TrustedIdentityIndex) -> String {
  let directMatch = identity.match(texts: texts)
  if directMatch.source == .phoneNumber,
    let source = texts.first(where: { text in
      let digits = digitsOnly(text)
      return identity.digitVariants.contains(where: {
        digits == $0 || (!digits.isEmpty && digits.contains($0))
      })
    })
  {
    return source.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  if directMatch.source == .uniqueContactAlias,
    let source = texts.first(where: { text in
      let normalized = normalizeSearchText(text)
      return identity.uniqueAliases.contains(where: {
        containsNormalizedPhrase(normalized, phrase: $0)
      })
    })
  {
    let cleaned = removeFaceTimeWords(source)
    return looksLikeHumanCallerIdentity(cleaned) ? cleaned : "unavailable"
  }

  for text in texts {
    let cleaned = removeFaceTimeWords(text)
    guard looksLikeHumanCallerIdentity(cleaned) else { continue }
    return cleaned
  }
  return "unavailable"
}

func removeFaceTimeWords(_ input: String) -> String {
  var output = input
  let variants = ["FaceTime Video", "FaceTime Audio", "FaceTime Call"]
  for variant in variants {
    output = output.replacingOccurrences(
      of: variant, with: "", options: [.caseInsensitive, .diacriticInsensitive])
  }
  output = output.trimmingCharacters(in: CharacterSet(charactersIn: " ,:-–—\n\t"))
  return output.trimmingCharacters(in: .whitespacesAndNewlines)
}

enum GatekeeperIdentityDecision: Equatable, Sendable {
  case answerTrusted
  case declineNonMatch
  case waitForIdentity
}

func gatekeeperIdentityDecision(identityMatch: IdentityMatch, callerText: String)
  -> GatekeeperIdentityDecision
{
  if identityMatch.isTrusted {
    return .answerTrusted
  }
  // Only missing/generic identity receives the short grace period. A visible
  // human name or number is explicit evidence of a non-match and can be declined.
  if callerText == "unavailable" || !looksLikeHumanCallerIdentity(callerText) {
    return .waitForIdentity
  }
  return .declineNonMatch
}

func privacySafeCallerState(identityMatch: IdentityMatch, callerText: String) -> String {
  if identityMatch.isTrusted { return "trusted" }
  if callerText == "unavailable" || !looksLikeHumanCallerIdentity(callerText) {
    return "unverified"
  }
  if identityMatch.source == .ambiguousContactAlias { return "ambiguous" }
  return "untrusted"
}
