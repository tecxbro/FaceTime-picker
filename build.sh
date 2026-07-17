#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
BUILD_DIR="$ROOT/build"
BINARY="$BUILD_DIR/FaceTimePicker"
SOURCES=("$ROOT"/Sources/*.swift(N))
if (( ${#SOURCES[@]} == 0 )); then
  print -u2 "No Swift sources found under $ROOT/Sources."
  exit 1
fi
PLIST="$ROOT/Resources/Info.plist"

mkdir -p "$BUILD_DIR"
needs_build=0
if [[ ! -x "$BINARY" ]]; then
  needs_build=1
else
  for input in "${SOURCES[@]}" "$PLIST"; do
    if [[ "$input" -nt "$BINARY" ]]; then needs_build=1; break; fi
  done
fi

if (( needs_build )); then
  print "Building FaceTimePicker with Swift 6..."
  xcrun --find swiftc >/dev/null
  xcrun swiftc -swift-version 6 -strict-concurrency=minimal -O \
    -framework AppKit -framework ApplicationServices -framework Contacts \
    "${SOURCES[@]}" -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist \
    -Xlinker "$PLIST" -o "$BINARY"
  /usr/bin/codesign --force --sign - --identifier com.tecxbro.FaceTimePicker "$BINARY" >/dev/null
  print "Built: $BINARY"
else
  print "Build is current: $BINARY"
fi
print "$BINARY"
