#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
OUT="${TMPDIR:-/tmp}/FaceTimePickerCoreTests"

# These files contain the platform-independent identity and configuration logic.
# Keeping this list explicit prevents macOS UI code from leaking into fast unit tests.
xcrun swiftc -swift-version 6 \
  "$ROOT/Sources/CoreLogic.swift" \
  "$ROOT/Sources/TrustedCallerModels.swift" \
  "$ROOT/Sources/IdentitySourceConfiguration.swift" \
  "$ROOT/Sources/TrustedCallerSource.swift" \
  "$ROOT/Tests/CoreLogicTests.swift" \
  -o "$OUT"

"$OUT"
