#!/bin/zsh
set -eu
ROOT="${0:A:h:h}"
BUILD="${BUILD_PRODUCTS_DIR:-$ROOT/DerivedData/Build/Products/Debug}"
if [[ ! -f "$BUILD/libNearbyShare.dylib" ]]; then
  print -u2 'Build the Debug QuickShareMac scheme with -derivedDataPath DerivedData first.'
  exit 1
fi
OUTPUT="$(mktemp -d "${TMPDIR:-/tmp/}quickshare-protocol-tests.XXXXXX")"
trap 'rm -f "$OUTPUT/sending-tests"; rmdir "$OUTPUT"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library -I "$BUILD" -L "$BUILD" \
  -Xlinker -rpath -Xlinker "$BUILD" -lNearbyShare \
  "$ROOT/Tests/SendingIntegrationTests.swift" -o "$OUTPUT/sending-tests"
DYLD_LIBRARY_PATH="$BUILD:${DYLD_LIBRARY_PATH:-}" "$OUTPUT/sending-tests"
