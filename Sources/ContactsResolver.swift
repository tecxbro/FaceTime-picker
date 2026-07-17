#if os(macOS)
@preconcurrency import AppKit
@preconcurrency import ApplicationServices
@preconcurrency import Contacts
import Darwin
import Foundation

final class ContactPermissionResult: @unchecked Sendable {
  private let lock = NSLock()
  private var storedGranted = false
  private var storedError: Error?

  func set(granted: Bool, error: Error?) {
    lock.lock()
    storedGranted = granted
    storedError = error
    lock.unlock()
  }

  func read() -> (Bool, Error?) {
    lock.lock()
    defer { lock.unlock() }
    return (storedGranted, storedError)
  }
}

struct ContactResolution: Sendable {
  let index: TrustedIdentityIndex
  let accessGranted: Bool
  let warning: String?
}

final class ContactResolutionResult: @unchecked Sendable {
  private let lock = NSLock()
  private var value: ContactResolution?

  func set(_ resolution: ContactResolution) {
    lock.lock()
    value = resolution
    lock.unlock()
  }

  func read() -> ContactResolution? {
    lock.lock()
    defer { lock.unlock() }
    return value
  }
}

func requestContactsAccess(store: CNContactStore) -> (Bool, String?) {
  switch CNContactStore.authorizationStatus(for: .contacts) {
  case .authorized:
    return (true, nil)
  case .denied:
    return (
      false,
      "Contacts access is denied. Saved-name callers cannot be verified; only raw phone-number text can match."
    )
  case .restricted:
    return (
      false,
      "Contacts access is restricted. Saved-name callers cannot be verified; only raw phone-number text can match."
    )
  case .notDetermined:
    let result = ContactPermissionResult()
    let semaphore = DispatchSemaphore(value: 0)
    store.requestAccess(for: .contacts) { granted, error in
      result.set(granted: granted, error: error)
      semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 30)
    let (granted, error) = result.read()
    if granted { return (true, nil) }
    return (
      false,
      error.map { "Contacts permission failed: \($0.localizedDescription)" }
        ?? "Contacts permission was not granted."
    )
  case .limited:
    return (
      true,
      "Contacts access is limited. Every trusted contact must be included in the allowed set, or saved-name matching will fail closed."
    )
  @unknown default:
    return (false, "Unknown Contacts authorization state. Saved-name matching is disabled.")
  }
}

func contactLabels(_ contact: CNContact) -> Set<String> {
  var labels: Set<String> = []
  if let fullName = CNContactFormatter.string(from: contact, style: .fullName),
    isUsableAlias(fullName)
  {
    labels.insert(fullName.trimmingCharacters(in: .whitespacesAndNewlines))
  }
  if isUsableAlias(contact.nickname) {
    labels.insert(contact.nickname.trimmingCharacters(in: .whitespacesAndNewlines))
  }
  return labels
}

func resolveTrustedIdentities(numbers: [String]) -> ContactResolution {
  // The raw-number index remains usable even when Contacts permission or lookup fails.
  let baseIndex = TrustedIdentityIndex(configuredNumbers: numbers)
  let store = CNContactStore()
  let (granted, permissionWarning) = requestContactsAccess(store: store)
  guard granted else {
    return ContactResolution(index: baseIndex, accessGranted: false, warning: permissionWarning)
  }

  let keys: [CNKeyDescriptor] = [
    CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
    CNContactPhoneNumbersKey as CNKeyDescriptor,
    CNContactNicknameKey as CNKeyDescriptor,
  ]
  let request = CNContactFetchRequest(keysToFetch: keys)
  request.unifyResults = true

  let trustedVariants = Set(numbers.flatMap { canonicalPhoneVariants($0) })
  var labelsByContact: [String: Set<String>] = [:]
  var aliasOwners: [String: Set<String>] = [:]
  var trustedContactIDs: Set<String> = []

  do {
    try store.enumerateContacts(with: request) { contact, _ in
      let labels = contactLabels(contact)
      labelsByContact[contact.identifier] = labels

      // Count every owner of an alias, not only trusted contacts. A name shared
      // with any other contact is ambiguous and must not become trusted.
      for label in labels {
        aliasOwners[normalizeSearchText(label), default: []].insert(contact.identifier)
      }

      let hasTrustedNumber = contact.phoneNumbers.contains { labeledValue in
        let contactVariants = canonicalPhoneVariants(labeledValue.value.stringValue)
        return !contactVariants.isDisjoint(with: trustedVariants)
      }
      if hasTrustedNumber {
        trustedContactIDs.insert(contact.identifier)
      }
    }
  } catch {
    return ContactResolution(
      index: baseIndex,
      accessGranted: false,
      warning: "Could not enumerate Contacts. Saved-name matching is disabled."
    )
  }

  var uniqueAliases: Set<String> = []
  var ambiguousAliases: Set<String> = []
  for contactID in trustedContactIDs {
    for label in labelsByContact[contactID] ?? [] {
      let normalized = normalizeSearchText(label)
      guard isUsableAlias(normalized) else { continue }
      if (aliasOwners[normalized]?.count ?? 0) == 1 {
        uniqueAliases.insert(normalized)
      } else {
        ambiguousAliases.insert(normalized)
      }
    }
  }

  let index = TrustedIdentityIndex(
    configuredNumbers: numbers,
    uniqueAliases: uniqueAliases,
    ambiguousAliases: ambiguousAliases,
    matchingContactCount: trustedContactIDs.count
  )
  return ContactResolution(index: index, accessGranted: true, warning: permissionWarning)
}

func resolveTrustedIdentitiesOffMain(numbers: [String]) -> ContactResolution {
  // Contacts enumeration and its permission callback can block. Keep that work
  // off the main run loop used by Accessibility observation and call actions.
  let result = ContactResolutionResult()
  let semaphore = DispatchSemaphore(value: 0)
  DispatchQueue.global(qos: .userInitiated).async {
    result.set(resolveTrustedIdentities(numbers: numbers))
    semaphore.signal()
  }
  _ = semaphore.wait(timeout: .now() + 40)
  return result.read()
    ?? ContactResolution(
      index: TrustedIdentityIndex(configuredNumbers: numbers),
      accessGranted: false,
      warning: "Contacts lookup timed out. Saved-name matching is disabled for this snapshot."
    )
}

#endif
