#!/bin/zsh
set -eu
ROOT="${0:A:h:h}"
OUTPUT="$(mktemp -d "${TMPDIR:-/tmp/}quickshare-update-tests.XXXXXX")"
trap 'rm -f "$OUTPUT/update-tests"; rmdir "$OUTPUT"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library \
  "$ROOT/QuickShareMac/UpdateChecker.swift" "$ROOT/Tests/UpdateCheckerTests.swift" \
  -o "$OUTPUT/update-tests"
"$OUTPUT/update-tests"
