#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}"
OUT="${TMPDIR:-/tmp}/FaceTimePickerCoreTests"
xcrun swiftc -swift-version 6 \
  "$ROOT/Sources/CoreLogic.swift" \
  "$ROOT/Sources/TrustedCallerModels.swift" \
  "$ROOT/Sources/IdentitySourceConfiguration.swift" \
  "$ROOT/Sources/TrustedCallerSource.swift" \
  "$ROOT/Tests/CoreLogicTests.swift" \
  -lsqlite3 \
  -o "$OUT"
"$OUT"
