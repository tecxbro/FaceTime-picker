# FaceTime Picker — local edition

A native Swift 6 macOS helper that watches incoming FaceTime notifications and applies a local allowlist.

- **Detector:** logs incoming-call detection and never presses a button.
- **Trusted answer:** answers trusted callers and leaves everyone else ringing.
- **Gatekeeper:** answers trusted callers and declines explicit non-matches.
- Missing or internal caller text receives a 900 ms grace period before Gatekeeper declines the call.

This is the `local` branch. It performs no network requests. The `main` branch is the database/API-backed edition.

## Requirements

- macOS 14.4 or newer
- FaceTime configured on the Mac
- Xcode Command Line Tools with Swift 6
- Accessibility permission for the compiled `FaceTimePicker` binary
- Contacts permission when FaceTime displays a saved contact name instead of a number

Install the command-line tools if needed:

```zsh
xcode-select --install
```

## Fork, clone, and run

```zsh
git clone --branch local --single-branch https://github.com/tecxbro/FaceTime-picker.git
cd FaceTime-picker
zsh ./run.sh
```

`run.sh` builds the helper and guides you through two choices:

1. where trusted numbers come from;
2. which safety mode to run.

The first launch asks macOS for Accessibility permission. Enable the compiled executable under:

**System Settings → Privacy & Security → Accessibility**

Then run `zsh ./run.sh` again.

Stop the helper with **Control+C**.

## Trusted caller sources

### Option 1: type numbers in Terminal

Choose option 1 in `run.sh`, then enter one or more numbers separated by commas.

```text
+1 202 555 0147, +44 20 7946 0958
```

The values stay only in the running process. They are not written to disk or included in normal logs.

### Option 2: local SQLite

Choose option 2 in `run.sh`. The script creates this database by default:

```text
local-data/trusted-callers.sqlite3
```

It creates the required table and asks for trusted numbers when the table is empty:

```sql
CREATE TABLE trusted_callers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  phone_number TEXT NOT NULL UNIQUE,
  enabled INTEGER NOT NULL DEFAULT 1
);
```

Only rows with `enabled = 1` are trusted. The helper opens the database read-only and refreshes the allowlist every 30 seconds.

Manage the database with the built-in `sqlite3` command:

```zsh
sqlite3 local-data/trusted-callers.sqlite3
```

Useful statements:

```sql
SELECT * FROM trusted_callers;
INSERT INTO trusted_callers (phone_number, enabled) VALUES ('+1 202 555 0147', 1);
UPDATE trusted_callers SET enabled = 0 WHERE id = 1;
DELETE FROM trusted_callers WHERE id = 1;
```

Local database files are ignored by Git.

## Safety modes

Start with **Detector**. Confirm that the correct caller is recognized before enabling call actions.

### Detector

Read-only. It never answers or declines.

### Trusted answer

Automatically answers a trusted caller. Other callers keep ringing.

### Gatekeeper

Answers a trusted caller and declines a caller whose visible identity does not match.

If caller identity is blank or is only an internal macOS Accessibility label such as `widgets-overlay-view`, the helper waits 900 ms and checks again. It does not treat that internal label as a real caller name.

Answering a FaceTime call exposes the Mac's camera and microphone. `run.sh` requires an explicit `ENABLE` confirmation before Trusted Answer or Gatekeeper mode starts.

## Test and build

Run all core tests, the SQLite fixture test, the privacy regression scan, plist validation, and the native macOS build:

```zsh
zsh ./test.sh
```

Build without running tests:

```zsh
zsh ./build.sh
```

The executable is created at:

```text
build/FaceTimePicker
```

## Code map

- `Sources/CoreLogic.swift` — phone normalization, alias matching, and caller decisions.
- `Sources/TrustedCallerSource.swift` — Terminal and read-only SQLite allowlists.
- `Sources/ContactsResolver.swift` — maps configured numbers to unique local Contacts aliases.
- `Sources/AccessibilitySupport.swift` — safe wrappers around macOS Accessibility APIs.
- `Sources/CallInspection.swift` — recognizes the incoming FaceTime notification and its controls.
- `Sources/NotificationCenter*.swift` — observer, polling, deduplication, and Answer/Decline actions.
- `Sources/IdentityRefresh.swift` — refreshes SQLite and fails closed after a stale-cache limit.
- `Tests/CoreLogicTests.swift` — regression tests for matching, identity grace, and SQLite filtering.

The source is split by responsibility so reviewers can inspect call detection, identity matching, and button actions independently.

## Privacy and failure behavior

- No trusted number is hardcoded in the repository.
- The local branch contains no HTTP client or cloud identity endpoint.
- Normal logs report `trusted`, `untrusted`, `ambiguous`, or `unverified`; raw caller text is off by default.
- SQLite is opened read-only by the Swift process.
- If SQLite refresh keeps failing until the configured stale limit expires, the allowlist is cleared and no caller is trusted until the database recovers.

## Limitations

- This relies on macOS Accessibility details that Apple does not document as a stable FaceTime API.
- Re-test after major macOS updates.
- Answer and Decline labels currently assume an English macOS interface.
- Detection can begin only after macOS exposes the incoming-call controls to Accessibility.

## License

MIT — see `LICENSE`.
