# FaceTime Picker — Local Branch

This branch is the offline/local edition of FaceTime Picker. It keeps the tested Phase 3 behavior:

- trusted caller → Answer
- non-matching caller → Decline
- missing or internal caller identity → wait 900 ms, re-check, then fail closed

`main` is unchanged. This branch does not require a cloud database or network endpoint.

## Choose a local trusted-caller source

### Option 1: type numbers in Terminal

Leave these variables unset:

```zsh
unset FACETIME_PICKER_SQLITE_PATH
unset FACETIME_PICKER_IDENTITY_FILE
```

Run a launcher. FaceTime Picker asks:

```text
Enter trusted phone number(s), separated by commas:
```

The numbers remain only in the running process. They are not written to disk or printed in logs.

### Option 2: local SQLite database

Create a local database:

```zsh
zsh "./Initialize Local SQLite.command"
```

Then set its path:

```zsh
export FACETIME_PICKER_SQLITE_PATH="$PWD/local-data/trusted-callers.sqlite3"
```

Expected schema:

```sql
CREATE TABLE trusted_callers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  phone_number TEXT NOT NULL UNIQUE,
  enabled INTEGER NOT NULL DEFAULT 1
);
```

Only rows with `enabled = 1` are trusted. The database is opened read-only by the app and refreshed every 30 seconds by default.

Custom table or column names are supported through:

```zsh
export FACETIME_PICKER_SQLITE_TABLE="trusted_callers"
export FACETIME_PICKER_SQLITE_PHONE_COLUMN="phone_number"
export FACETIME_PICKER_SQLITE_ENABLED_COLUMN="enabled"
```

Names are strictly validated before being inserted into SQL.

### Option 3: local JSON file

```zsh
cp config/trusted-callers.example.json config/trusted-callers.local.json
export FACETIME_PICKER_IDENTITY_FILE="$PWD/config/trusted-callers.local.json"
```

Real local databases, JSON files, proof markers, builds, and environment files are ignored by Git.

## Run safely

### Phase 1 — read-only detector

```zsh
zsh "./Build and Run Detector.command"
```

### Phase 2 — answer trusted callers only

```zsh
zsh "./Mark Phase 1 Proven.command"
zsh "./Build and Run Trusted Answer.command"
```

### Phase 3 — answer trusted, decline others

```zsh
zsh "./Mark Phase 2 Proven.command"
zsh "./Build and Run Gatekeeper.command"
```

The launchers still require explicit confirmation before enabling camera/microphone exposure or declining calls.

## Permissions

Add the compiled executable—not the folder or launcher—to:

```text
System Settings → Privacy & Security → Accessibility
```

The executable is:

```text
build/FaceTimePicker
```

Allow Contacts access so saved FaceTime display names can be resolved from the typed or locally stored phone numbers.

## Privacy and safety

- No trusted phone number is committed.
- Terminal-entered numbers are held only in memory.
- SQLite is opened read-only.
- Database identifiers are validated against a strict allowlist.
- Caller text is hidden by default.
- Internal Accessibility identifiers such as `widgets-overlay-view` are not caller identities.
- If a refreshable local source becomes unavailable and the cache expires, the app clears the allowlist and fails closed.

## Validate

```zsh
zsh "./Validate Core Logic.command"
zsh ./build.sh
```

This project depends on undocumented macOS Accessibility behavior and must be retested after major macOS updates.
