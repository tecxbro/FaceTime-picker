#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}"
DB_DIR="$ROOT/local-data"
DB_PATH="${FACETIME_PICKER_SQLITE_PATH:-$DB_DIR/trusted-callers.sqlite3}"
DB_PATH="${DB_PATH/#\~/$HOME}"

command -v sqlite3 >/dev/null || { print "The sqlite3 command was not found on this Mac."; exit 1; }
mkdir -p "${DB_PATH:h}"

print -n "Enter a trusted phone number: "
IFS= read -r number
print -r -- "$number" | /usr/bin/grep -Eq '^[0-9+() .-]+$' || { print "Use only digits, spaces, +, -, and parentheses."; exit 1; }
digits="$(print -r -- "$number" | /usr/bin/tr -cd '0-9')"
(( ${#digits} >= 7 && ${#digits} <= 15 )) || { print "The number must contain 7 to 15 digits."; exit 1; }
escaped="${number//\'/\'\'}"

/usr/bin/sqlite3 "$DB_PATH" <<SQL
PRAGMA journal_mode=WAL;
CREATE TABLE IF NOT EXISTS trusted_callers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  phone_number TEXT NOT NULL UNIQUE,
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1))
);
INSERT INTO trusted_callers (phone_number, enabled)
VALUES ('$escaped', 1)
ON CONFLICT(phone_number) DO UPDATE SET enabled = 1;
SQL

print "Local database ready: $DB_PATH"
print "Before running FaceTime Picker, use:"
print "  export FACETIME_PICKER_SQLITE_PATH=\"$DB_PATH\""
