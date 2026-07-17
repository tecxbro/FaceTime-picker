#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
OUT="${TMPDIR:-/tmp}/FaceTimePickerCoreTests"

zsh -n "$ROOT/run.sh" "$ROOT/build.sh"

if grep -RIn -E \
  'Run mode:|Detector —|Trusted answer|Gatekeeper —|Phase [123]|enable phase' \
  "$ROOT/README.md" "$ROOT/run.sh"; then
  print -u2 "The public local setup still exposes internal stage or mode terminology."
  exit 1
fi

if ! grep -Fq 'exec "$ROOT/build/FaceTimePicker" --mode gatekeeper --confirmed-enable' "$ROOT/run.sh"; then
  print -u2 "The launcher must start the complete trusted-caller behavior automatically."
  exit 1
fi

if [[ "$(grep -c 'Type ENABLE to start:' "$ROOT/run.sh")" != "1" ]]; then
  print -u2 "The launcher must have exactly one ENABLE confirmation."
  exit 1
fi

xcrun --find swiftc >/dev/null
xcrun swiftc -swift-version 6 -strict-concurrency=minimal \
  "$ROOT/Sources/CoreLogic.swift" \
  "$ROOT/Sources/IdentitySourceConfiguration.swift" \
  "$ROOT/Sources/TrustedCallerSource.swift" \
  "$ROOT/Tests/CoreLogicTests.swift" \
  -lsqlite3 \
  -o "$OUT"
"$OUT"

zsh "$ROOT/build.sh" >/dev/null
/usr/bin/plutil -lint "$ROOT/Resources/Info.plist" >/dev/null

if grep -RIn --exclude-dir=.git -E \
  'FACETIME_PICKER_IDENTITY_URL|URLSession|HTTPURLResponse|216.?571.?5884|Paras Mama|--trusted-number' \
  "$ROOT/Sources" "$ROOT/Tests" "$ROOT/README.md" "$ROOT/run.sh"; then
  print -u2 "Privacy regression scan failed."
  exit 1
fi

print "ALL CHECKS PASSED"
