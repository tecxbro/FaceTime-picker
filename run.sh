#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
cd "$ROOT"

print "FaceTime Picker — local edition"
print ""
print "Trusted caller source:"
print "  1) Type number(s) in Terminal"
print "  2) Use a local SQLite database"
read "source_choice?Choose [1]: "
source_choice="${source_choice:-1}"
unset FACETIME_PICKER_SQLITE_PATH

case "$source_choice" in
  1)
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
      for value in ${(s:,:)raw_numbers}; do
        number="$(print -r -- "$value" | /usr/bin/xargs)"
        digits="${number//[^0-9]/}"
        if (( ${#digits} < 7 || ${#digits} > 15 )); then
          print -u2 "Invalid phone number: $number"
          exit 2
        fi
        escaped="${number//\'/\'\'}"
        /usr/bin/sqlite3 "$database_path" \
          "INSERT OR REPLACE INTO trusted_callers (phone_number, enabled) VALUES ('$escaped', 1);"
      done
    fi
    export FACETIME_PICKER_SQLITE_PATH="$database_path"
    ;;
  *)
    print -u2 "Choose 1 or 2."
    exit 2
    ;;
esac

print ""
print "Run mode:"
print "  1) Detector — log calls only"
print "  2) Trusted answer — answer trusted callers, leave others ringing"
print "  3) Gatekeeper — answer trusted callers and decline others"
read "mode_choice?Choose [1]: "
mode_choice="${mode_choice:-1}"

case "$mode_choice" in
  1) mode="detector" ;;
  2) mode="answer-trusted" ;;
  3) mode="gatekeeper" ;;
  *)
    print -u2 "Choose 1, 2, or 3."
    exit 2
    ;;
esac

arguments=(--mode "$mode")
if [[ "$mode" != "detector" ]]; then
  print ""
  print "WARNING: answering a FaceTime call exposes the camera and microphone."
  if [[ "$mode" == "gatekeeper" ]]; then
    print "Gatekeeper mode also declines callers that do not safely match the allowlist."
  fi
  read "confirmation?Type ENABLE to continue: "
  if [[ "$confirmation" != "ENABLE" ]]; then
    print "Cancelled."
    exit 0
  fi
  arguments+=(--confirmed-enable)
fi

zsh "$ROOT/build.sh"
exec "$ROOT/build/FaceTimePicker" "${arguments[@]}"
