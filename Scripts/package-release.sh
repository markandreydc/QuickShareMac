#!/bin/zsh
set -eu
ROOT="${0:A:h:h}"
BUILD="$ROOT/DerivedData/Distribution"
PACKAGES="$ROOT/DerivedData/SourcePackages"
APP="$BUILD/Build/Products/Release/QuickShareMac.app"
ZIP="$ROOT/QuickShareMac.app.zip"

# This produces a complete local ad-hoc signature, not Developer ID signing or
# notarization. A public release will still show macOS's unidentified-app warning.
xcodebuild -project "$ROOT/QuickShareMac.xcodeproj" -scheme QuickShareMac \
  -configuration Release -derivedDataPath "$BUILD" \
  -clonedSourcePackagesDirPath "$PACKAGES" \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  ONLY_ACTIVE_ARCH=NO 'ARCHS=arm64 x86_64' MACOSX_DEPLOYMENT_TARGET=12.0 build

# Include the licenses for code linked into the app and extension. These are
# collected from the exact dependency checkouts used by this build.
python3 - "$ROOT" "$APP" "$PACKAGES" <<'PY'
from pathlib import Path
import shutil,sys
root,app,packages=map(Path,sys.argv[1:])
destination=app/'Contents/Resources/Licenses'
destination.mkdir(parents=True,exist_ok=True)
def copy_license(source,target):
    # SwiftPM checkouts can be read-only. Do not propagate that mode into the
    # generated release resources, which need to be replaceable on later builds.
    if target.exists(): target.chmod(0o644)
    shutil.copyfile(source,target)
copy_license(root/'UNLICENSE',destination/'QuickShareMac-UNLICENSE.txt')
for name in ['swift-protobuf','SwiftECC','ASN1','BigInt','qrcode','swift-qrcode-generator','SwiftImageReadWrite']:
    licenses=[path for path in (packages/'checkouts'/name).glob('LICENSE*') if path.is_file()]
    if not licenses: raise SystemExit('Missing dependency license: '+name)
    for path in licenses: copy_license(path,destination/(name+'-'+path.name+'.txt'))
(destination/'Acknowledgements.txt').write_text(
    'Developed by Mark Andrey · github.com/markandreydc\n\n'
    'QuickShareMac is a fork of NearDrop by grishka and contributors.\n'
    'Original project and protocol implementation: https://github.com/grishka/NearDrop\n'
    'Dependency license texts are included alongside this acknowledgement.\n',encoding='utf-8')
PY

# Resource additions require resealing the outer bundle. Embedded code retains
# the individual signatures produced by Xcode; never use --deep when signing.
codesign --force --sign - --timestamp=none --preserve-metadata=identifier,entitlements "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
for binary in \
  "$APP/Contents/MacOS/QuickShareMac" \
  "$APP/Contents/Frameworks/libNearbyShare.dylib" \
  "$APP/Contents/PlugIns/ShareExtension.appex/Contents/MacOS/ShareExtension" \
  "$APP/Contents/PlugIns/ShareExtension.appex/Contents/Frameworks/libNearbyShare.dylib"; do
  lipo "$binary" -verify_arch arm64
  lipo "$binary" -verify_arch x86_64
done

# Keep the .app as the archive's top-level item, preserving its metadata.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
(
  cd "$ROOT"
  shasum -a 256 QuickShareMac.app.zip > QuickShareMac.app.zip.sha256
)
print "Created $ZIP"
print "Ad-hoc signed; NOT notarized. macOS 12+, Apple Silicon and Intel."
