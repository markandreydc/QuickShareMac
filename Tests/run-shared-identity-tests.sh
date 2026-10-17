#!/bin/zsh
set -eu
ROOT="${0:A:h:h}"
OUTPUT="$(mktemp -d "${TMPDIR:-/tmp/}quickshare-shared-name-tests.XXXXXX")"
trap 'python3 -c "import shutil,sys; shutil.rmtree(sys.argv[1])" "$OUTPUT"' EXIT
python3 - "$ROOT" "$OUTPUT" <<'PY'
from pathlib import Path
import plistlib,shutil,subprocess,sys,uuid
root,output=map(Path,sys.argv[1:])
domain='me.grishka.QuickShareMac.Identity.Test.'+uuid.uuid4().hex
executables=[]
for role,access in [('Host','read-write'),('Extension','read-only')]:
    app=output/(role+'.app')
    executable=app/'Contents/MacOS/probe'
    executable.parent.mkdir(parents=True)
    (app/'Contents/Info.plist').write_bytes(plistlib.dumps({
        'CFBundleIdentifier':domain+'.'+role,'CFBundleExecutable':'probe'}))
    entitlement=output/(role+'.entitlements')
    entitlement.write_bytes(plistlib.dumps({
        'com.apple.security.app-sandbox':True,
        'com.apple.security.temporary-exception.shared-preference.'+access:[domain]}))
    if not executables:
        subprocess.run(['xcrun','swiftc','-parse-as-library',
            str(root/'NearbyShare/LocalDeviceIdentity.swift'),str(root/'Tests/IdentityPreferenceProbe.swift'),
            '-o',str(executable)],check=True)
    else: shutil.copy2(executables[0],executable)
    subprocess.run(['codesign','--force','--sign','-','--entitlements',str(entitlement),str(app)],check=True)
    executables.append(executable)
def run(executable,action,*args):
    return subprocess.check_output([str(executable),domain,action,*args],text=True).strip()
host,extension=executables
try:
    assert run(host,'get')=='System Mac'
    assert run(host,'set','Shared Test Mac 🖥️')=='Shared Test Mac 🖥️'
    assert run(extension,'get')=='Shared Test Mac 🖥️', 'Extension cannot read the shared name'
    run(extension,'set','Must not overwrite')
    assert run(host,'get')=='Shared Test Mac 🖥️', 'Read-only extension changed the host preference'
    print('Passed 4 sandboxed shared-name checks')
finally: run(host,'clear')
PY
