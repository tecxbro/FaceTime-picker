#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
MODE="${1:-detector}"
if (( $# > 0 )); then shift; fi

validate_configuration() {
  local has_url=0
  local has_file=0
  [[ -n "${FACETIME_PICKER_IDENTITY_URL:-}" ]] && has_url=1
  [[ -n "${FACETIME_PICKER_IDENTITY_FILE:-}" ]] && has_file=1

  if (( has_url + has_file != 1 )); then
    cat >&2 <<'EOF'
Configure exactly one trusted-caller source:

  export FACETIME_PICKER_IDENTITY_FILE="$PWD/config/trusted-callers.local.json"

or:

  export FACETIME_PICKER_IDENTITY_URL="https://your-service.example/trusted-callers"
EOF
    exit 1
  fi

  if (( has_url )) && [[ "$FACETIME_PICKER_IDENTITY_URL" != https://* ]]; then
    print -u2 "FACETIME_PICKER_IDENTITY_URL must use HTTPS."
    exit 1
  fi
}

# The first argument owns the run mode. Prevent extra arguments from bypassing
# the action-mode confirmation performed by this launcher.
for argument in "$@"; do
  case "$argument" in
    --mode|--confirmed-enable)
      print -u2 "Do not pass $argument directly; choose the mode as run.sh's first argument."
      exit 2
      ;;
  esac
done

validate_configuration
zsh "$ROOT/build.sh"
BINARY="$ROOT/build/FaceTimePicker"
/usr/bin/open -a FaceTime
sleep 0.3

case "$MODE" in
  detector)
    print "Starting read-only detector mode. No call control will be pressed."
    exec "$BINARY" --mode detector "$@"
    ;;
  answer-trusted)
    cat <<'EOF'
WARNING: trusted callers will be answered automatically.
Answering a call can expose the camera and microphone.
Untrusted, ambiguous, and unverified callers remain ringing.
EOF
    print -n "Type ENABLE ANSWER exactly to continue: "
    IFS= read -r confirmation
    [[ "$confirmation" == "ENABLE ANSWER" ]] || { print "Cancelled."; exit 1; }
    exec "$BINARY" --mode answer-trusted --confirmed-enable "$@"
    ;;
  gatekeeper)
    cat <<'EOF'
WARNING: gatekeeper mode answers trusted callers and declines explicit non-matches.
Missing or generic caller identity receives a 900 ms recheck before decline.
Answering a call can expose the camera and microphone.
EOF
    print -n "Type ENABLE GATEKEEPER exactly to continue: "
    IFS= read -r confirmation
    [[ "$confirmation" == "ENABLE GATEKEEPER" ]] || { print "Cancelled."; exit 1; }
    exec "$BINARY" --mode gatekeeper --confirmed-enable "$@"
    ;;
  *)
    print -u2 "Usage: zsh ./run.sh detector|answer-trusted|gatekeeper [runtime options]"
    exit 2
    ;;
esac
