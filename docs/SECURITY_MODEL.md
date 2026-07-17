# Security model

FaceTime Picker automates sensitive call controls and must be treated as a privileged local process. This document describes the intended trust boundaries, privacy defaults, and fail-closed behavior. For vulnerability reporting, see [SECURITY.md](../SECURITY.md).

## Protected assets

- Trusted caller phone numbers.
- Local Contacts names and nicknames.
- Provider endpoint location.
- Authentication header values.
- FaceTime caller identity.
- Camera and microphone exposure caused by auto-answer.
- The ability to press Answer or Decline through Accessibility.

## Trust boundaries

```text
Database or provider
        |
        | narrow authenticated HTTPS response
        v
FaceTime Picker process
        |
        | local Contacts and Accessibility APIs
        v
FaceTime / Notification Center call controls
```

The macOS process is trusted to:

- read its configured identity source
- read enough local Contacts data to map trusted numbers to unique aliases
- inspect Notification Center Accessibility elements
- press visible call controls only in explicitly enabled action modes

The provider is trusted to return the correct allowlist. The provider should not expose unrestricted database access to the macOS process.

## Secrets

No real phone numbers, API URLs, authorization values, or provider credentials belong in Git.

Runtime request headers are configured indirectly:

```zsh
export FACETIME_PICKER_HEADER_ENVS="Authorization=FACETIME_PICKER_AUTHORIZATION"
export FACETIME_PICKER_AUTHORIZATION="Bearer secret-at-runtime"
```

The program reads the secret from the named environment variable. It does not accept the secret as a command-line argument and does not print request headers or the endpoint URL in normal logs.

For long-lived deployments:

- use a secret manager or a wrapper that reads macOS Keychain
- avoid placing secrets in shell history
- restrict the environment inherited by unrelated child processes
- rotate provider credentials after accidental disclosure

## Provider access

Prefer a narrow authenticated endpoint that can only read enabled trusted-caller records.

Do not give the macOS client:

- a Supabase service-role or secret key
- a Firebase/Google service-account private key
- direct PostgreSQL, MySQL, or MongoDB administrator credentials
- write or delete access to the backing database

Provider-side controls should include:

- TLS
- authentication
- least-privilege database permissions
- rate limiting
- response-size limits
- audit logs that do not record complete phone-number lists unnecessarily

Supabase service-role and secret keys bypass Row Level Security and must remain inside trusted server-side code such as an Edge Function. Firebase secret parameters must be bound only to the function that needs them.

## Identity-source validation

The client rejects:

- non-HTTPS remote URLs
- conflicting file and URL configuration
- malformed header mappings
- missing mapped secret variables
- HTTP status codes other than `200`
- responses larger than 256 KB
- malformed or unsupported JSON
- unsupported schema versions
- invalid enabled phone numbers
- empty effective allowlists

One invalid enabled phone number rejects the complete response. This avoids silently trusting a partially understood configuration.

## Contact matching

The provider supplies phone numbers only. FaceTime may display a saved contact name instead of the raw number, so the client resolves trusted numbers against local Contacts.

An alias is trusted only when:

1. the contact contains a configured trusted-number variant; and
2. the normalized full name or nickname belongs to exactly one local contact.

When multiple contacts own the same alias, the alias is marked ambiguous and is not trusted.

If Contacts access is denied, restricted, unavailable, or times out, only raw-number matching remains trusted. Limited Contacts access works only for trusted contacts included in the allowed set.

## Accessibility identity filtering

Notification Center exposes many internal labels that are not caller identity. The client filters known examples including:

- Accessibility roles and subroles
- Notification Center labels
- FaceTime marker text
- Answer, Accept, Decline, Reject, Hang Up, and End Call labels
- known overlay identifiers such as `widgets-overlay-view`

A missing or internal label is not treated as a human-readable non-match.

## Gatekeeper decisions

| Identity state | Gatekeeper behavior |
|---|---|
| Trusted phone number | Answer immediately. |
| Unique trusted Contacts alias | Answer immediately. |
| Explicit human-readable non-match | Decline immediately. |
| Ambiguous Contacts alias | Decline immediately. |
| Missing, generic, or internal identity | Wait 900 ms, reinspect, then decline if still unverified. |

The 900 ms grace period applies only to missing or generic identity. It does not apply to an explicit non-match or ambiguous alias.

## Action safeguards

- Detector mode cannot press call controls.
- Action modes require the launcher to supply `--confirmed-enable`.
- Trusted-answer mode requires the local `.phase1-proven` marker and an exact confirmation phrase.
- Gatekeeper mode requires `.phase2-proven` and a different exact confirmation phrase.
- Active calls are fingerprinted to reduce duplicate processing.
- A short cooldown reduces repeated presses caused by duplicate Accessibility events.
- A pending unverified call is re-inspected before decline.

These safeguards reduce accidental activation but do not convert undocumented Accessibility automation into a formally verified system.

## Logging

Default logs report operational fields such as:

- privacy-safe caller state
- match source
- control availability
- timing
- scan counts
- action result
- refresh state

Default logs do not print:

- raw caller text
- allowlist numbers
- Contacts aliases
- endpoint URL
- authentication headers or values
- JSON payloads

`--log-caller-text` deliberately weakens this protection for local diagnostics and emits a privacy warning. Treat those logs as sensitive personal data.

## Refresh and stale snapshots

The first valid snapshot is required before monitoring starts.

If a later refresh fails, the last valid snapshot remains active until the effective stale deadline. The effective deadline is never shorter than the refresh interval. After expiration, the monitor receives an empty identity index and trusts nobody until recovery.

An empty provider response is rejected rather than installed as an empty snapshot. Consequently, a previous valid snapshot can remain active until the stale deadline. Immediate local revocation requires stopping the process or using an operational design that accounts for this behavior.

## Failure behavior

| Failure | Behavior |
|---|---|
| Missing or conflicting source configuration | Exit before monitoring. |
| Accessibility permission missing | Prompt asynchronously, report the error, and exit. |
| Initial source load fails | Exit before monitoring. |
| Contacts unavailable | Continue with raw-number matching only. |
| Notification Center unavailable | Exit before monitoring. |
| Observer creation fails | Exit before monitoring. |
| Refresh fails before stale deadline | Keep the last valid snapshot. |
| Stale deadline expires | Clear all trusted identities. |
| Action press fails | Log the Accessibility error; do not assume success. |
| Unknown caller in trusted-answer mode | Leave ringing. |
| Explicit non-match in gatekeeper mode | Decline. |
| Missing identity in gatekeeper mode | Recheck for 900 ms, then decline if still unverified. |

## Known limitations

- FaceTime and Notification Center Accessibility structure is undocumented and may change.
- The current executable is ad-hoc signed, not notarized.
- Accessibility permission is powerful and applies to the local executable.
- English action labels are recognized; other languages may not work safely.
- CI cannot validate real FaceTime calls or button presses.
- Contact changes are re-evaluated during identity refresh rather than through a dedicated Contacts-change subscription.
- The client does not provide remote process control or immediate provider-driven shutdown.

## Operator responsibilities

Before action modes:

- complete the manual test matrix on the target macOS version
- verify the provider response and authentication
- understand camera and microphone exposure from auto-answer
- keep a terminal available to stop the process with Control+C
- avoid running multiple copies
- repeat detector testing after macOS updates

## Out of scope

This security model does not claim protection against:

- a compromised macOS user account
- malware already holding Accessibility permission
- a compromised trusted-caller provider
- malicious modification of the local executable or launch scripts
- a compromised Apple ID, FaceTime account, or local Contacts database
- physical access to an unlocked Mac
