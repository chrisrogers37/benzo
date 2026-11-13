#!/bin/bash
# Inspect only a task-owned account-free artifact; never open/install its app.
set -euo pipefail
umask 077
[[ $# == 1 && "$1" == /* && -d "$1" && ! -L "$1" ]] || { echo 'Pass the absolute packaging output directory' >&2; exit 1; }
output=$1
[[ ! -e "$output/INCOMPLETE" ]] || { echo 'Refusing an incomplete artifact' >&2; exit 1; }
printf 'Read-only DMG inspection has not completed.\n' > "$output/MOUNT_VALIDATION_INCOMPLETE"
[[ ! -f "$output/mounted-validation.txt" ]] || rm "$output/mounted-validation.txt"
manifest="$output/artifact.txt"
metadata() { awk -F ': ' -v key="$1" '$1 == key {print $2}' "$manifest"; }
[[ "$(metadata Mode)" == development ]] || { echo 'Expected a development artifact' >&2; exit 1; }
version=$(metadata Version); build=$(metadata Build)
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$build" =~ ^[1-9][0-9]*$ ]] || exit 1
dmg="$output/Benzo-$version-development.dmg"
[[ -f "$dmg" && ! -L "$dmg" ]] || exit 1
(cd "$output" && shasum -a 256 -c SHA256SUMS)
task=$(mktemp -d "${TMPDIR:-/tmp}/benzo-dmg-inspect.XXXXXX")
mount="$task/mount"
mkdir -m 755 "$mount"
attached=false
cleanup() {
    result=$?
    trap - EXIT
    if [[ "$attached" == true ]] && ! hdiutil detach "$mount"; then
        printf 'Could not detach task-owned mount %s; inspection directory retained.\n' "$mount" >&2
        exit 1
    fi
    rm -rf -- "$task"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# Mark before attaching so even an incomplete attachment gets a bounded cleanup
# attempt at this unique mountpoint. Never detach a discovered/global device.
attached=true
# Keep the actual attachment response even when inspection fails and scratch is
# removed, so CI preserves mount diagnostics alongside its incomplete marker.
hdiutil attach -readonly -nobrowse -noautoopen -mountpoint "$mount" -plist "$dmg" > "$output/mounted-attachment.plist" 2> "$output/mounted-attachment.log"
python3 - "$mount" "$output/mounted-attachment.plist" "$version" "$build" <<'PY'
import os, pathlib, plistlib, sys
mount = pathlib.Path(sys.argv[1])
def require(condition, message):
    if not condition: raise SystemExit(message)
with open(sys.argv[2], 'rb') as f: attachment = plistlib.load(f)
mounted = [x['mount-point'] for x in attachment['system-entities'] if 'mount-point' in x]
require(len(mounted) == 1 and isinstance(mounted[0], str) and pathlib.Path(mounted[0]).is_absolute(), 'Unexpected mount result')
# hdiutil canonicalizes /var to /private/var (and other ancestor symlinks).
# Accept only that same existing directory, never another mount or device.
require(pathlib.Path(mounted[0]).resolve(strict=True) == mount.resolve(strict=True), 'Unexpected mount result')
require(mount.stat().st_mode & 0o777 == 0o755, 'Mounted root must be readable by other accounts')
require((mount / 'Applications').is_symlink() and os.readlink(mount / 'Applications') == '/Applications', 'Applications link differs')
require('FUNCTIONAL ACCOUNT-FREE BUILD' in (mount / 'README.txt').read_text(), 'Account-free build disclosure is missing')
app = mount / 'Benzo Development.app'
require(app.is_dir() and not app.is_symlink(), 'Development app is missing')
for relative in ['Contents', 'Contents/MacOS']:
    require((app / relative).is_dir() and not (app / relative).is_symlink(), 'Bundle directory differs')
require({p.name for p in (app / 'Contents/MacOS').iterdir()} == {'Benzo', 'BenzoCommand'}, 'Executable structure differs')
for relative in ['Contents/Frameworks', 'Contents/PlugIns', 'Contents/XPCServices', 'Contents/Library/LoginItems', 'Contents/Library/LaunchDaemons']:
    require(not os.path.lexists(app / relative), 'Unexpected bundled service or nested code: ' + relative)
for relative in ['Contents/Info.plist', 'Contents/MacOS/Benzo', 'Contents/MacOS/BenzoCommand']:
    require((app / relative).is_file() and not (app / relative).is_symlink(), 'Missing/linked bundle file: ' + relative)
for name in ['Benzo', 'BenzoCommand']:
    require((app / 'Contents/MacOS' / name).stat().st_mode & 0o777 == 0o755, 'Executable modes differ')
with (app / 'Contents/Info.plist').open('rb') as f: info = plistlib.load(f)
for key, value in {'CFBundleIdentifier': 'com.benzo.app', 'CFBundleExecutable': 'Benzo',
                   'CFBundleShortVersionString': sys.argv[3], 'CFBundleVersion': sys.argv[4],
                   'CFBundleDisplayName': 'Benzo Development'}.items():
    require(info.get(key) == value, 'Packaged metadata differs: ' + key)

PY
app="$mount/Benzo Development.app"
for component in app command; do
    target="$app"; executable="$app/Contents/MacOS/Benzo"; identifier=com.benzo.app
    if [[ "$component" == command ]]; then target="$app/Contents/MacOS/BenzoCommand"; executable="$target"; identifier=com.chrisrogers37.benzo-command; fi
    archs=$(lipo -archs "$executable")
    [[ "$archs" == 'arm64 x86_64' || "$archs" == 'x86_64 arm64' ]] || exit 1
    codesign --verify --strict --all-architectures "$target"
    for arch in arm64 x86_64; do
        codesign -dv --verbose=4 --arch "$arch" "$target" > "$task/signature.txt" 2>&1
        grep -qx "Identifier=$identifier" "$task/signature.txt"
        grep -qx 'Signature=adhoc' "$task/signature.txt"
        codesign -d --entitlements - --xml --arch "$arch" "$target" > "$task/entitlements.plist" 2> "$task/entitlements.log"
        python3 - "$task/entitlements.plist" <<'PY'
import pathlib, plistlib, sys
data = pathlib.Path(sys.argv[1]).read_bytes()
entitlements = plistlib.loads(data) if data else {}
if entitlements != {}: raise SystemExit('Packaged executable has unexpected entitlements')
PY
        codesign --verify --strict --arch "$arch" -R "=identifier \"$identifier\"" "$target"
    done
done
codesign --verify --deep --strict --all-architectures "$app"
hdiutil detach "$mount"
attached=false
printf 'Account-free DMG inspected read-only; app/command signatures, metadata, architectures and absence of bundled services verified. No app was launched.\n' > "$output/mounted-validation.txt"
rm "$output/MOUNT_VALIDATION_INCOMPLETE"
cat "$output/mounted-validation.txt"
