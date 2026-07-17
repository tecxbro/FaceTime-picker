#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}"
cat <<'EOF'
Full gatekeeper declines callers not safely matched to the current allowlist.
Only continue after trusted auto-answer and identity-source configuration are proven.
EOF
print -n "Type PHASE2 PROVEN exactly: "
IFS= read -r confirmation
[[ "$confirmation" == "PHASE2 PROVEN" ]] || { print "Cancelled."; exit 1; }
/usr/bin/touch "$ROOT/.phase2-proven"
print "Full gatekeeper unlocked locally."
