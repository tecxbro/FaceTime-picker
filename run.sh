#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
cd "$ROOT"

print "FaceTime Picker — local edition"
print ""

if [[ "$(uname -s)" != "Darwin" ]]; then
  print -u2 "FaceTime Picker runs only on macOS."
  exit 1
fi

if ! /usr/bin/xcrun --find swiftc >/dev/null 2>&1; then
  print -u2 "Swift is not available. Install Apple's Command Line Tools first:"
  print -u2 "  xcode-select --install"
  exit 1
fi

print "How should FaceTime Picker load trusted callers?"
print "  1) Type phone number(s) in Terminal"
print "  2) Use a local SQLite database"
read "source_choice?Choose [1]: "
source_choice="${source_choice:-1}"
unset FACETIME_PICKER_SQLITE_PATH
terminal_numbers=""

case "$source_choice" in
  1)
    read "terminal_numbers?Enter trusted phone number(s), separated by commas: "

    valid_count=0
    for value in ${(s:,:)terminal_numbers}; do
      number="$(print -r -- "$value" | /usr/bin/xargs)"
      [[ -z "$number" ]] && continue

      digits="${number//[^0-9]/}"
      if (( ${#digits} < 7 || ${#digits} > 15 )); then
        print -u2 "Invalid phone number: $number"
        exit 2
      fi
      (( valid_count += 1 ))
    done

    if (( valid_count == 0 )); then
      print -u2 "Enter at least one trusted phone number."
      exit 2
    fi
    ;;
  2)
    default_database="$ROOT/local-data/trusted-callers.sqlite3"
    read "database_path?SQLite path [$default_database]: "
    database_path="${database_path:-$default_database}"
    database_path="${database_path/#\~/$HOME}"
    mkdir -p "${database_path:h}"

    /usr/bin/sqlite3 "$database_path" <<'SQL'
CREATE TABLE IF NOT EXISTS trusted_callers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  phone_number TEXT NOT NULL UNIQUE,
  enabled INTEGER NOT NULL DEFAULT 1
);
SQL

    enabled_count="$(/usr/bin/sqlite3 "$database_path" 'SELECT COUNT(*) FROM trusted_callers WHERE enabled = 1;')"
    if [[ "$enabled_count" == "0" ]]; then
      print "The database has no enabled trusted callers."
      read "raw_numbers?Enter trusted phone number(s), separated by commas: "

      inserted_count=0
      for value in ${(s:,:)raw_numbers}; do
        number="$(print -r -- "$value" | /usr/bin/xargs)"
        [[ -z "$number" ]] && continue

        digits="${number//[^0-9]/}"
        if (( ${#digits} < 7 || ${#digits} > 15 )); then
          print -u2 "Invalid phone number: $number"
          exit 2
        fi

        escaped="${number//\'/\'\'}"
        /usr/bin/sqlite3 "$database_path" \
          "INSERT OR REPLACE INTO trusted_callers (phone_number, enabled) VALUES ('$escaped', 1);"
        (( inserted_count += 1 ))
      done

      if (( inserted_count == 0 )); then
        print -u2 "Enter at least one trusted phone number."
        exit 2
      fi
    fi

    export FACETIME_PICKER_SQLITE_PATH="$database_path"
    ;;
  *)
    print -u2 "Choose 1 or 2."
    exit 2
    ;;
esac

print ""
print "FaceTime Picker will answer trusted callers automatically and decline callers that do not safely match."
print "Answering a FaceTime call turns on this Mac's camera and microphone."
read "confirmation?Type ENABLE to start: "
if [[ "$confirmation" != "ENABLE" ]]; then
  print "Cancelled. Nothing was enabled."
  exit 0
fi

print ""
zsh "$ROOT/build.sh"
print ""
print "Starting FaceTime Picker. Press Control+C to stop."

if [[ "$source_choice" == "1" ]]; then
  exec "$ROOT/build/FaceTimePicker" --mode gatekeeper --confirmed-enable <<< "$terminal_numbers"
else
  exec "$ROOT/build/FaceTimePicker" --mode gatekeeper --confirmed-enable
fi
