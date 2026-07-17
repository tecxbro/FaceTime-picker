# Security and privacy — local branch

## Local-only identity sources

This branch does not connect to a network identity API. Trusted numbers come from one of:

- interactive Terminal input held in memory;
- a local SQLite database opened read-only;
- a local JSON file.

Do not commit real phone numbers, database files, JSON allowlists, proof markers, or environment files. The repository ignores common SQLite and local-data paths.

## SQLite safety

- The app opens SQLite with `SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX`.
- Table and column names must match `[A-Za-z_][A-Za-z0-9_]*`.
- The query reads only the configured phone column where the enabled column equals `1`.
- Use ordinary filesystem permissions to restrict who can read or modify the database.

## Contact matching

Numbers are mapped to local Contacts aliases. An alias is trusted only when it uniquely identifies a contact associated with a configured number. Ambiguous aliases fail closed.

## Accessibility identity filtering

Internal Accessibility metadata such as `widgets-overlay-view`, AX roles, Notification Center labels, and button labels are not caller identities. If no human-readable identity is available, the full gatekeeper waits 900 ms and rechecks before declining.

## Logging

Default logs do not print configured phone numbers or caller text. The optional `--log-caller-text` diagnostic flag should not be used in shared logs.

## Failure behavior

- Local source cannot load at startup: exit without monitoring.
- Contacts unavailable: only raw-number matching is trusted.
- Refreshable local source cache expires: clear the allowlist and trust nobody until refresh succeeds.
- Unknown or ambiguous identity in full-gatekeeper mode: decline after the identity grace behavior.
