#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}"
PROOF_MARKER="$ROOT/.phase1-proven"
[[ -f "$PROOF_MARKER" ]] || { print "Trusted answer is locked. Run Mark Phase 1 Proven.command after detector testing."; exit 1; }
"$ROOT/scripts/validate-config.zsh"
cat <<'EOF'
WARNING: trusted auto-answer exposes the camera and microphone.
Unknown and ambiguous callers are left ringing in this mode.
EOF
print -n "Type ENABLE exactly to continue: "
IFS= read -r confirmation
[[ "$confirmation" == "ENABLE" ]] || { print "Cancelled."; exit 1; }
"$ROOT/build.sh"
BINARY="$ROOT/build/FaceTimePicker"
/usr/bin/open -a FaceTime
sleep 0.3
print "Trusted auto-answer enabled. Press Control+C to stop."
exec "$BINARY" --mode answer-trusted --confirmed-enable
