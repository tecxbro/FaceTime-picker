#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}"
cat <<'EOF'
Unlock only after the detector correctly recognizes trusted and untrusted calls,
including FaceTime Audio if you intend to use it.
EOF
print -n "Type PHASE1 PROVEN exactly: "
IFS= read -r confirmation
[[ "$confirmation" == "PHASE1 PROVEN" ]] || { print "Cancelled."; exit 1; }
/usr/bin/touch "$ROOT/.phase1-proven"
print "Trusted-answer mode unlocked locally."
