#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
BUILD_DIR="$ROOT/build"
BINARY="$BUILD_DIR/FaceTimePicker"
PLIST="$ROOT/Resources/Info.plist"
SOURCES=("$ROOT"/Sources/*.swift(N))

if (( ${#SOURCES[@]} == 0 )); then
  print -u2 "No Swift sources found under $ROOT/Sources."
  exit 1
fi

mkdir -p "$BUILD_DIR"
needs_build=0
if [[ ! -x "$BINARY" ]]; then
  needs_build=1
else
  # Rebuild only when source or embedded permission metadata is newer.
  for input in "${SOURCES[@]}" "$PLIST"; do
    if [[ "$input" -nt "$BINARY" ]]; then needs_build=1; break; fi
  done
fi

if (( needs_build )); then
  print "Building FaceTimePicker with Swift 6..."
  xcrun --find swiftc >/dev/null

  # Info.plist is embedded in the executable so macOS can display the Contacts
  # permission reason even though this project does not create an app bundle.
  xcrun swiftc -swift-version 6 -strict-concurrency=minimal -O \
    -framework AppKit -framework ApplicationServices -framework Contacts \
    "${SOURCES[@]}" -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist \
    -Xlinker "$PLIST" -o "$BINARY"

  # Ad-hoc signing is enough for local use. This is not notarization or distribution signing.
  /usr/bin/codesign --force --sign - --identifier com.tecxbro.FaceTimePicker "$BINARY" >/dev/null
  print "Built: $BINARY"
else
  print "Build is current: $BINARY"
fi

print "$BINARY"
