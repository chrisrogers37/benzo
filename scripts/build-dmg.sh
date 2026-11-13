#!/bin/bash
# Adapted from isolated PR #102 packaging; never installs or launches Benzo.
set -euo pipefail
umask 077

usage() {
    cat <<'USAGE'
Usage: build-dmg.sh --mode development|developer-id --output-dir <new-absolute-directory>
                    [--build-number <positive-integer>]
                    [--signing-identity <certificate-SHA1> --team-id <team-ID>]
                    [--notarize --notary-profile <existing-keychain-profile>]

Requires macOS and full Xcode. Development uses ad-hoc signatures, no credentials
or network, and supports power access after explicit setup. Developer ID signs with a
secure timestamp; it does not upload unless --notarize is explicitly supplied.
No release is published, app launched, power tool installed, or host setting changed.
USAGE
}
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
mode= output= build_number= identity= team= profile= notarize=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help) usage; exit 0 ;;
        --notarize)
            [[ "$notarize" == false ]] || fail 'Duplicate --notarize'
            notarize=true; shift; continue ;;
        --mode) option_var=mode ;;
        --output-dir) option_var=output ;;
        --build-number) option_var=build_number ;;
        --signing-identity) option_var=identity ;;
        --team-id) option_var=team ;;
        --notary-profile) option_var=profile ;;
        *) fail 'Unknown argument (see --help)' ;;
    esac
    [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || fail "Missing value for $1"
    [[ -z "${!option_var}" ]] || fail "Duplicate $1"
    printf -v "$option_var" '%s' "$2"
    shift 2
done
[[ "$mode" == development || "$mode" == developer-id ]] || fail 'An explicit development or developer-id mode is required'
[[ "$output" == /* && "$output" != */ && "$output" != *$'\n'* ]] || fail 'Output must be a new absolute directory without a trailing slash'
[[ -z "$build_number" || "$build_number" =~ ^[1-9][0-9]*$ ]] || fail 'Build number must be a positive integer'
if [[ "$mode" == developer-id ]]; then
    [[ "$identity" =~ ^[A-Fa-f0-9]{40}$ ]] || fail 'Developer ID requires a certificate SHA1'
    [[ "$team" =~ ^[A-Z0-9]{10}$ ]] || fail 'Developer ID requires a team ID'
    identity=$(printf '%s' "$identity" | tr '[:lower:]' '[:upper:]')
else
    [[ -z "$identity$team$profile" && "$notarize" == false ]] || fail 'Development mode cannot use signing credentials or notarization'
fi
if [[ "$notarize" == true ]]; then
    [[ "$mode" == developer-id && "$profile" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || fail 'Notarization requires Developer ID mode and an existing keychain profile'
else
    [[ -z "$profile" ]] || fail '--notary-profile requires explicit --notarize'
fi

parent=$(dirname "$output"); leaf=$(basename "$output")
[[ "$leaf" != . && "$leaf" != .. && -d "$parent" ]] || fail 'Output parent must already exist'
output="$(cd "$parent" && pwd -P)/$leaf"
[[ ! -e "$output" && ! -L "$output" ]] || fail 'Output already exists; choose a new task-owned directory'
tools=(xcodebuild python3 lipo codesign ditto hdiutil shasum mktemp git)
[[ "$mode" != developer-id ]] || tools+=(security)
[[ "$notarize" == false ]] || tools+=(xcrun spctl)
for tool in "${tools[@]}"; do command -v "$tool" >/dev/null || fail "Missing tool: $tool"; done
[[ "$(uname -s)" == Darwin ]] || fail 'Packaging requires macOS and full Xcode'
# Consume all version output before matching, including Xcode's separate writes.
xcode_version=$(xcodebuild -version) || fail 'Could not read Xcode version'
grep -q '^Xcode ' <<< "$xcode_version" || fail 'Full Xcode is required'

mkdir -m 700 "$output" || fail 'Could not reserve new output directory'
scratch=
cleanup() {
    result=$?
    trap - EXIT
    [[ -z "$scratch" ]] || rm -rf -- "$scratch"
    if [[ $result -ne 0 ]]; then printf 'Packaging failed; INCOMPLETE evidence retained in %s\n' "$output" >&2; fi
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
printf 'Packaging has not completed. Do not distribute partial output.\n' > "$output/INCOMPLETE"
scratch=$(mktemp -d "$output/.work.XXXXXX")
repo=$(cd "$(dirname "$0")/.." && pwd -P)
archive="$scratch/Benzo.xcarchive"
app="$scratch/Benzo.app"
build_args=(-project "$repo/Benzo/Benzo.xcodeproj" -scheme Benzo -configuration Release
    -derivedDataPath "$scratch/DerivedData" 'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO)
[[ -z "$build_number" ]] || build_args+=("CURRENT_PROJECT_VERSION=$build_number")
xcodebuild "${build_args[@]}" -showBuildSettings -json > "$output/build-settings.json"
setting() {
    python3 - "$output/build-settings.json" "$1" <<'PY'
import json, sys
settings = [x['buildSettings'] for x in json.load(open(sys.argv[1]))
            if x.get('buildSettings', {}).get('TARGET_NAME') == 'Benzo']
if len(settings) != 1: raise SystemExit('Expected exactly one Benzo build-settings target')
print(settings[0][sys.argv[2]])
PY
}
version=$(setting MARKETING_VERSION)
[[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || fail 'Marketing version must be an unambiguous three-part numeric version'
effective_build=$(setting CURRENT_PROJECT_VERSION)
[[ "$effective_build" =~ ^[1-9][0-9]*$ ]] || fail 'Effective build number must be a positive integer'
[[ -z "$build_number" || "$build_number" == "$effective_build" ]] || fail 'Build number override was not applied'
build_args+=("MARKETING_VERSION=$version" "CURRENT_PROJECT_VERSION=$effective_build")
source_commit=$(git -C "$repo" rev-parse HEAD)
[[ "$source_commit" =~ ^[a-f0-9]{40}$ ]] || fail 'Could not identify source commit'
source_state=clean
source_status=$(git -C "$repo" status --porcelain) || fail 'Could not inspect source tree'
[[ -z "$source_status" ]] || source_state=dirty
printf '%s\n' "$xcode_version" > "$output/xcode-version.txt"

if [[ "$mode" == developer-id ]]; then
    security find-identity -v -p codesigning > "$scratch/identities.txt"
    awk -v cert="$identity" -v team="$team" '
        $2 == cert && index($0, "\"Developer ID Application: ") && index($0, "(" team ")\"") { found=1 }
        END { exit !found }
    ' "$scratch/identities.txt" || fail 'Selected valid Developer ID Application identity/team was not found'
fi
printf 'Archiving Benzo %s (%s), mode %s\n' "$version" "$effective_build" "$mode"
xcodebuild "${build_args[@]}" -archivePath "$archive" archive > "$output/archive.log" 2>&1
ditto "$archive/Products/Applications/Benzo.app" "$app"

# Validate the app and one-shot command topology before signing. New nested code needs an explicit
# signing decision; --deep is used for verification only.
python3 - "$app" "$version" "$effective_build" "$mode" <<'PY'
import os, pathlib, plistlib, sys
app = pathlib.Path(sys.argv[1])
def require(condition, message):
    if not condition: raise SystemExit(message)
require(app.is_dir() and not app.is_symlink(), 'Archived app is missing or a symlink')
for relative in ['Contents', 'Contents/MacOS']:
    path = app / relative
    require(path.is_dir() and not path.is_symlink(), 'Invalid bundle directory: ' + relative)
for relative in ['Contents/Info.plist', 'Contents/MacOS/Benzo', 'Contents/MacOS/BenzoCommand']:
    path = app / relative
    require(path.is_file() and not path.is_symlink(), 'Missing or linked bundle file: ' + relative)
for name in ['Benzo', 'BenzoCommand']:
    require(os.access(app / 'Contents/MacOS' / name, os.X_OK), 'Not executable: ' + name)
require({p.name for p in (app / 'Contents/MacOS').iterdir()} == {'Benzo', 'BenzoCommand'}, 'Unexpected embedded executable')
for relative in ['Contents/Frameworks', 'Contents/PlugIns', 'Contents/XPCServices', 'Contents/Library/LoginItems', 'Contents/Library/LaunchDaemons']:
    require(not os.path.lexists(app / relative), 'Unreviewed nested code: ' + relative)
info_path = app / 'Contents/Info.plist'
with info_path.open('rb') as f: info = plistlib.load(f)
for key, expected in {'CFBundleIdentifier': 'com.benzo.app', 'CFBundleExecutable': 'Benzo',
                      'CFBundleShortVersionString': sys.argv[2], 'CFBundleVersion': sys.argv[3]}.items():
    require(info.get(key) == expected, 'App metadata mismatch: ' + key)
if sys.argv[4] == 'development':
    info['CFBundleDisplayName'] = 'Benzo Development'
    info['CFBundleName'] = 'Benzo Development'
    with info_path.open('wb') as f: plistlib.dump(info, f)
PY
command_tool="$app/Contents/MacOS/BenzoCommand"
for executable in "$app/Contents/MacOS/Benzo" "$command_tool"; do
    archs=$(lipo -archs "$executable")
    [[ "$archs" == 'arm64 x86_64' || "$archs" == 'x86_64 arm64' ]] || fail 'Both executables must contain exactly arm64 and x86_64'
done
check_entitlements() {
    python3 - "$1" <<'PY'
import pathlib, plistlib, sys
data = pathlib.Path(sys.argv[1]).read_bytes()
# codesign emits no stdout when the signature has no entitlement blob.
actual = plistlib.loads(data) if data else {}
if actual != {}: raise SystemExit('Unexpected entitlements in a Benzo executable')
PY
}
sign_args=(--force --options runtime)
if [[ "$mode" == developer-id ]]; then sign_args+=(--sign "$identity" --timestamp)
else sign_args+=(--sign - --timestamp=none); fi
# Sign each executable explicitly, inside out, without additional entitlements.
# Functional power access does not require a Developer ID or an app role marker.
(umask 022; codesign "${sign_args[@]}" --identifier com.chrisrogers37.benzo-command "$command_tool") > "$output/sign-command.log" 2>&1
(umask 022; codesign "${sign_args[@]}" --identifier com.benzo.app "$app") > "$output/sign-app.log" 2>&1
for component in app command; do
    target="$app"; identifier=com.benzo.app
    if [[ "$component" == command ]]; then target="$command_tool"; identifier=com.chrisrogers37.benzo-command; fi
    codesign --verify --strict --all-architectures "$target" > "$output/verify-$component.log" 2>&1
    for arch in arm64 x86_64; do
        signature="$output/signature-$component-$arch.txt"
        codesign -dv --verbose=4 --arch "$arch" "$target" > "$signature" 2>&1
        grep -qx "Identifier=$identifier" "$signature" || fail 'Signing identifier mismatch'
        codesign -d --entitlements - --xml --arch "$arch" "$target" > "$output/entitlements-$component-$arch.plist" 2>> "$output/verify-$component.log"
        check_entitlements "$output/entitlements-$component-$arch.plist"
        requirement="=identifier \"$identifier\""
        if [[ "$mode" == developer-id ]]; then
            grep -q '^Authority=Developer ID Application:' "$signature" || fail 'Developer ID signature is missing'
            grep -qx "TeamIdentifier=$team" "$signature" || fail 'Signing team mismatch'
            grep -Eq '^CodeDirectory .*flags=.*\(.*runtime.*\)' "$signature" || fail 'Hardened runtime is missing'
            grep -q '^Timestamp=' "$signature" || fail 'Secure timestamp is missing'
            requirement="$requirement and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"$team\""
        else
            grep -qx 'Signature=adhoc' "$signature" || fail 'Development component is not ad-hoc signed'
        fi
        codesign --verify --strict --arch "$arch" -R "$requirement" "$target" >> "$output/verify-$component.log" 2>&1
    done
done
codesign --verify --deep --strict --all-architectures "$app" >> "$output/verify-app.log" 2>&1

notarize_and_staple() {
    local receipt="$output/notary-$3.json" staple_log="$output/staple-$3.log" submission_id submission_result=0
    xcrun notarytool submit "$1" --keychain-profile "$profile" --wait --output-format json > "$receipt" || submission_result=$?
    submission_id=$(python3 - "$receipt" <<'PY'
import json, sys, uuid
identifier = json.load(open(sys.argv[1])).get('id')
uuid.UUID(identifier)
print(identifier)
PY
)
    # Preserve warnings/rejection detail, including Accepted submission logs.
    xcrun notarytool log "$submission_id" --keychain-profile "$profile" "$output/notary-$3-log.json"
    [[ "$submission_result" == 0 ]] || fail 'Notarization command failed; submission evidence was retained'
    python3 - "$receipt" <<'PY'
import json, sys
if json.load(open(sys.argv[1])).get('status') != 'Accepted': raise SystemExit('Apple notarization did not return Accepted')
PY
    xcrun stapler staple "$2" > "$staple_log" 2>&1
    xcrun stapler validate "$2" >> "$staple_log" 2>&1
}
if [[ "$notarize" == true ]]; then
    ditto -c -k --keepParent "$app" "$scratch/Benzo.zip"
    notarize_and_staple "$scratch/Benzo.zip" "$app" app
    codesign --verify --deep --strict --all-architectures "$app" >> "$output/verify-app.log" 2>&1
    spctl --assess --type execute --verbose=4 "$app" > "$output/assess-app.log" 2>&1
fi

volume=Benzo; app_name=Benzo.app
trust='Developer ID signed; not notarized; no Gatekeeper acceptance claimed'
if [[ "$mode" == development ]]; then
    volume='Benzo Development'; app_name='Benzo Development.app'; suffix=-development
    trust='FUNCTIONAL ACCOUNT-FREE BUILD: ad-hoc signed; unnotarized; power access available after explicit administrator setup; native acceptance pending'
elif [[ "$notarize" == true ]]; then
    suffix=
    trust='Developer ID signed; Apple notarization Accepted for the app; DMG validation follows'
else suffix=-signed-unnotarized; fi
dmg_name="Benzo-$version$suffix.dmg"
dmg="$scratch/$dmg_name"
mkdir -m 755 "$scratch/dmg-root"
ditto "$app" "$scratch/dmg-root/$app_name"
ln -s /Applications "$scratch/dmg-root/Applications"
launch_guidance='macOS may block the first launch of this unnotarized build. If you trust this
copy, use the per-app Open Anyway option in System Settings > Privacy & Security,
then confirm Open. Never disable Gatekeeper or remove quarantine attributes.'
if [[ "$notarize" == true ]]; then
    launch_guidance='This build is Developer ID signed and notarized. Keep the normal macOS
security checks enabled when opening it.'
fi
(umask 022; cat > "$scratch/dmg-root/README.txt" <<README
$volume $version ($effective_build)

Drag $app_name to Applications to copy it. This disk image does not launch the
app, install a power tool, or change any power setting automatically.

$launch_guidance
After opening from Applications, choose Set Up Power Access for one explicit
administrator approval for the account using Benzo. On, Off, and quit then use
that limited grant without another administrator prompt. Repair/update or removal
of power access remains an explicit administrator action.

$trust
README
)
hdiutil create -volname "$volume" -srcfolder "$scratch/dmg-root" -format UDZO "$dmg" > "$output/dmg.log" 2>&1
hdiutil verify "$dmg" >> "$output/dmg.log" 2>&1
if [[ "$mode" == developer-id ]]; then
    codesign --sign "$identity" --timestamp "$dmg" > "$output/sign-dmg.log" 2>&1
    codesign --verify --strict "$dmg" > "$output/verify-dmg.log" 2>&1
    if [[ "$notarize" == true ]]; then
        notarize_and_staple "$dmg" "$dmg" dmg
        codesign --verify --strict "$dmg" >> "$output/verify-dmg.log" 2>&1
        spctl --assess --type open --context context:primary-signature --verbose=4 "$dmg" > "$output/assess-dmg.log" 2>&1
        trust='Developer ID signed; Apple notarization Accepted; app and DMG staples validated'
    fi
fi
printf 'Mode: %s\nSource commit: %s\nSource tree: %s\nVersion: %s\nBuild: %s\nApp and command architectures: arm64 x86_64\nTrust: %s\nNative acceptance: not performed by packaging\n' \
    "$mode" "$source_commit" "$source_state" "$version" "$effective_build" "$trust" > "$output/artifact.txt"
mv "$dmg" "$output/$dmg_name"
(cd "$output" && shasum -a 256 "$dmg_name" artifact.txt > SHA256SUMS && shasum -a 256 -c SHA256SUMS)
rm "$output/INCOMPLETE"
printf 'Artifact: %s/%s\n%s\n' "$output" "$dmg_name" "$trust"
