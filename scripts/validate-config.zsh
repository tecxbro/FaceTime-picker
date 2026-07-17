#!/bin/zsh
set -euo pipefail
has_url=0
has_file=0
[[ -n "${FACETIME_PICKER_IDENTITY_URL:-}" ]] && has_url=1
[[ -n "${FACETIME_PICKER_IDENTITY_FILE:-}" ]] && has_file=1
if (( has_url + has_file != 1 )); then
  cat <<'EOF'
Configure exactly one trusted-caller source before running:

  export FACETIME_PICKER_IDENTITY_URL="https://your-service.example/trusted-callers"

or for local development:

  export FACETIME_PICKER_IDENTITY_FILE="$PWD/config/trusted-callers.local.json"

See docs/IDENTITY_API.md.
EOF
  exit 1
fi
if (( has_url )) && [[ "$FACETIME_PICKER_IDENTITY_URL" != https://* ]]; then
  print "FACETIME_PICKER_IDENTITY_URL must use HTTPS."
  exit 1
fi
