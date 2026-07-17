#!/bin/zsh
set -euo pipefail

has_sqlite=0
has_file=0
[[ -n "${FACETIME_PICKER_SQLITE_PATH:-}" ]] && has_sqlite=1
[[ -n "${FACETIME_PICKER_IDENTITY_FILE:-}" ]] && has_file=1

if (( has_sqlite + has_file > 1 )); then
  cat <<'EOF'
Configure only one local trusted-caller source:

  FACETIME_PICKER_SQLITE_PATH
  FACETIME_PICKER_IDENTITY_FILE

Leave both unset to type trusted number(s) interactively in Terminal.
EOF
  exit 1
fi

if (( has_sqlite )) && [[ ! -f "${FACETIME_PICKER_SQLITE_PATH/#\~/$HOME}" ]]; then
  print "SQLite database not found: $FACETIME_PICKER_SQLITE_PATH"
  print "Run: zsh \"./Initialize Local SQLite.command\""
  exit 1
fi

if (( has_file )) && [[ ! -f "${FACETIME_PICKER_IDENTITY_FILE/#\~/$HOME}" ]]; then
  print "Local JSON identity file not found: $FACETIME_PICKER_IDENTITY_FILE"
  exit 1
fi
