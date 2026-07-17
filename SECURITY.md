# Security and privacy

## Secrets

- No phone numbers, API URLs, or credentials belong in Git.
- Runtime credentials are passed through environment variables referenced by `FACETIME_PICKER_HEADER_ENVS`.
- The program never logs header values or the endpoint URL.
- Production endpoints must use HTTPS.

For long-lived deployments, launch the process from a secret manager or a small wrapper that retrieves secrets from macOS Keychain rather than saving them in shell history.

## Database access

Prefer a narrow read-only API that returns only enabled trusted callers. Do not give the macOS process unrestricted database credentials. Apply row-level security or equivalent access controls at the provider.

## Contact matching

Phone numbers are fetched at runtime and mapped to local Contacts aliases. Aliases are trusted only when the displayed alias belongs to exactly one local contact. Ambiguous aliases fail closed.

## Accessibility identity filtering

Internal Accessibility metadata such as `widgets-overlay-view`, AX roles, Notification Center labels, and button labels are not treated as caller identity. If no human-readable identity is available, the full gatekeeper waits 900 ms and rechecks before declining.

## Logging

Default logs redact caller text and report only identity state. The optional `--log-caller-text` diagnostic flag is unsafe for shared logs.

## Failure behavior

- Source cannot load at startup: exit without monitoring.
- Contacts unavailable: only raw-number matching is trusted.
- Identity cache expires: clear the allowlist and trust nobody until refresh succeeds.
- Unknown or ambiguous identity in full-gatekeeper mode: decline after the configured grace behavior.
