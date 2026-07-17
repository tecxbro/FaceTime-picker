#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}"
"$ROOT/scripts/validate-config.zsh"
"$ROOT/build.sh"
BINARY="$ROOT/build/FaceTimePicker"
/usr/bin/open -a FaceTime
sleep 0.3
print "Starting the read-only detector. No calls will be answered or declined."
print "Press Control+C to stop."
exec "$BINARY" --mode detector
