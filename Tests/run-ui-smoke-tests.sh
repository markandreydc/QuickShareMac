#!/bin/zsh
set -eu
ROOT="${0:A:h:h}"
BUILD="${BUILD_PRODUCTS_DIR:-$ROOT/DerivedData/Build/Products/Debug}"
if [[ ! -f "$BUILD/libNearbyShare.dylib" ]]; then
  print -u2 'Build the Debug QuickShareMac scheme with -derivedDataPath DerivedData first.'
  exit 1
fi
OUTPUT="$(mktemp -d "${TMPDIR:-/tmp/}quickshare-ui-tests.XXXXXX")"
trap 'rm -f "$OUTPUT/ui-smoke-tests"; rmdir "$OUTPUT"' EXIT
xcrun swiftc -swift-version 5 -I "$BUILD" -L "$BUILD" \
  -Xlinker -rpath -Xlinker "$BUILD" -lNearbyShare \
  "$BUILD/QRCode.o" "$BUILD/QRCodeGenerator.o" "$BUILD/SwiftImageReadWrite.o" \
  "$ROOT/QuickShareMac/MainWindowViewController.swift" \
  "$ROOT/QuickShareMac/ReceivedFilesFolder.swift" \
  "$ROOT/QuickShareMac/SendViewController.swift" \
  "$ROOT/QuickShareMac/FolderCompressor.swift" \
  "$ROOT/QuickShareMac/IncomingRequestNotifications.swift" \
  "$ROOT/QuickShareMac/StatusBarMenu.swift" \
  "$ROOT/QuickShareMac/ReceivingAvailability.swift" \
  "$ROOT/QuickShareMac/UpdateChecker.swift" \
  "$ROOT/QuickShareMac/UpdateResultPresenter.swift" \
  "$ROOT/Shared/SendTransferViewController.swift" \
  "$ROOT/Shared/ShareHandoff.swift" \
  "$ROOT/ShareExtension/ShareViewController.swift" \
  "$ROOT/Tests/UISmokeTests.swift" -o "$OUTPUT/ui-smoke-tests"
DYLD_LIBRARY_PATH="$BUILD:${DYLD_LIBRARY_PATH:-}" "$OUTPUT/ui-smoke-tests"
