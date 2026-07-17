#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}"
PROOF_MARKER="$ROOT/.phase2-proven"
[[ -f "$PROOF_MARKER" ]] || { print "Full gatekeeper is locked. Run Mark Phase 2 Proven.command after trusted-answer testing."; exit 1; }
"$ROOT/scripts/validate-config.zsh"
cat <<'EOF'
WARNING: FULL FACETIME PICKER
- Trusted callers from the configured identity source are answered.
- Explicit non-matches are declined.
- Missing/generic identity receives a 900 ms grace period before decline.
- Auto-answer exposes the camera and microphone.
EOF
print -n "Type ENABLE GATEKEEPER exactly to continue: "
IFS= read -r confirmation
[[ "$confirmation" == "ENABLE GATEKEEPER" ]] || { print "Cancelled."; exit 1; }
"$ROOT/build.sh"
BINARY="$ROOT/build/FaceTimePicker"
/usr/bin/open -a FaceTime
sleep 0.3
print "Full gatekeeper enabled. Press Control+C to stop."
exec "$BINARY" --mode gatekeeper --confirmed-enable
