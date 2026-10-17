#!/bin/zsh
set -eu
ROOT="${0:A:h:h}"
# Keep signing enabled: the linker-only signature from CODE_SIGNING_ALLOWED=NO
# does not bind Info.plist or entitlements and is not a valid app-bundle signature.
xcodebuild -project "$ROOT/QuickShareMac.xcodeproj" -scheme QuickShareMac \
  -configuration Debug -derivedDataPath "$ROOT/DerivedData" \
  CODE_SIGNING_ALLOWED=YES build
APP="$ROOT/DerivedData/Build/Products/Debug/QuickShareMac.app"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv --verbose=2 "$APP"
print "Verified local development build: $APP"
