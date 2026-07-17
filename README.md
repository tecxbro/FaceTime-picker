# FaceTime Picker — local edition

A native Swift 6 macOS helper that watches incoming FaceTime notifications, answers trusted callers, and declines callers whose visible identity does not safely match your local allowlist.

This is the `local` branch. It makes no network requests. The `main` branch is the database/API-backed edition.

## Run it

Copy and paste this single command into Terminal:

```zsh
git clone --branch local --single-branch https://github.com/tecxbro/FaceTime-picker.git && cd FaceTime-picker && zsh ./run.sh
```

For later launches from the downloaded folder:

```zsh
zsh ./run.sh
```

That is the complete user flow. The launcher:

1. checks that the Mac has Swift available;
2. asks whether trusted callers should come from Terminal input or a local SQLite database;
3. builds the native helper automatically;
4. asks you to type `ENABLE` once;
5. starts FaceTime Picker.

There are no separate setup stages or feature-enablement commands.

Stop the helper at any time with **Control+C**.

## Requirements

- macOS 14.4 or newer
- FaceTime configured on the Mac
- Xcode Command Line Tools with Swift 6
- Accessibility permission for the compiled `FaceTimePicker` executable
- Contacts permission when FaceTime displays a saved contact name instead of a number

Install Apple's command-line tools when needed:

```zsh
xcode-select --install
```

## First-launch permissions

The first launch asks macOS for Accessibility permission. Add and enable the compiled executable here:

**System Settings → Privacy & Security → Accessibility**

The executable is located at:

```text
FaceTime-picker/build/FaceTimePicker
```

After granting permission, run this again:

```zsh
zsh ./run.sh
```

macOS may also request Contacts permission so configured numbers can match saved contact names.

## Trusted caller choices

### Type numbers in Terminal

Choose option 1 and enter one or more trusted numbers separated by commas:

```text
+1 202 555 0147, +44 20 7946 0958
```

The values remain only in the running process. They are not written to disk or included in normal logs.

### Use local SQLite

Choose option 2. By default, the launcher creates:

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

Only rows with `enabled = 1` are trusted. FaceTime Picker opens the database read-only and refreshes the allowlist every 30 seconds.

To manage the database manually:

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

## What happens while it runs

- A trusted caller is answered automatically.
- A visible caller identity that does not safely match the allowlist is declined.
- Blank or internal macOS Accessibility text gets a 900 ms grace period before a decision is made.
- Unknown, ambiguous, or stale identity data fails closed rather than being treated as trusted.

Answering a FaceTime call exposes the Mac's camera and microphone. The launcher therefore requires the explicit `ENABLE` confirmation every time it starts.

## Test or build manually

Run all core tests, the SQLite fixture test, privacy checks, plist validation, launcher checks, and the native macOS build:

```zsh
zsh ./test.sh
```

Build without starting the helper:

```zsh
zsh ./build.sh
```

The executable is created at:

```text
build/FaceTimePicker
```

## Code map

- `run.sh` — the single interactive setup, build, confirmation, and launch command.
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
- The `local` branch contains no HTTP client or cloud identity endpoint.
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
