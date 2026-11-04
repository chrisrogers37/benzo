#!/bin/bash
set -euo pipefail
umask 077

usage() {
    cat <<'USAGE'
Usage: build-dmg.sh --mode community|developer-id --output-dir <new-absolute-directory>
                    [--build-number <positive-integer>]
                    [--signing-identity <certificate-SHA1> --team-id <team-ID>
                     --notary-profile <configured-keychain-profile>]

Requires full Xcode. Developer ID mode uploads to Apple and requires all three
signing arguments. Community mode is explicitly ad-hoc signed and unnotarized.
No release is published, app launched, or system configuration changed.
USAGE
}
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }

mode= output= build_number= identity= team= profile=
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help) usage; exit 0 ;;
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
[[ "$mode" == community || "$mode" == developer-id ]] || fail 'An explicit distribution mode is required'
[[ "$output" == /* && "$output" != */ && "$output" != *$'\n'* ]] || fail 'Output must be a new absolute directory without a trailing slash'
[[ -z "$build_number" || "$build_number" =~ ^[1-9][0-9]*$ ]] || fail 'Build number must be a positive integer'
if [[ "$mode" == developer-id ]]; then
    [[ "$identity" =~ ^[A-Fa-f0-9]{40}$ ]] || fail 'Developer ID requires a certificate SHA1'
    [[ "$team" =~ ^[A-Z0-9]{10}$ ]] || fail 'Developer ID requires a team ID'
    [[ "$profile" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || fail 'Developer ID requires a configured keychain profile name'
    identity=$(printf '%s' "$identity" | tr '[:lower:]' '[:upper:]')
else
    [[ -z "$identity$team$profile" ]] || fail 'Community mode cannot use Developer ID arguments'
fi

parent=$(dirname "$output")
leaf=$(basename "$output")
[[ "$leaf" != . && "$leaf" != .. && -d "$parent" ]] || fail 'Output parent must already exist'
output="$(cd "$parent" && pwd -P)/$leaf"
[[ ! -e "$output" && ! -L "$output" ]] || fail 'Output already exists; choose a new task-owned directory'
tools=(xcodebuild plutil lipo codesign ditto hdiutil shasum mktemp)
[[ "$mode" != developer-id ]] || tools+=(security xcrun spctl)
for tool in "${tools[@]}"; do
    command -v "$tool" >/dev/null || fail "Missing tool: $tool"
done
[[ "$(uname -s)" == Darwin ]] || fail 'Packaging requires macOS and full Xcode'
# Drain Xcode's output before matching; grep -q must not close its pipe early.
xcode_version=$(xcodebuild -version) || fail 'Could not read Xcode version'
grep -q '^Xcode ' <<< "$xcode_version" || fail 'Full Xcode is required'

# Exclusive creation prevents reuse of a shared build directory. Only our private
# mktemp scratch is recursively deleted, including on failure or interruption.
mkdir -m 700 "$output" || fail 'Could not reserve new output directory'
scratch=
cleanup() {
    result=$?
    trap - EXIT
    [[ -z "$scratch" ]] || rm -rf -- "$scratch"
    if [[ $result -ne 0 ]]; then
        printf 'Packaging failed; incomplete evidence retained in %s\n' "$output" >&2
    fi
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
printf 'Packaging has not completed. Do not distribute partial output.\n' > "$output/INCOMPLETE"
scratch=$(mktemp -d "$output/.work.XXXXXX")
repo=$(cd "$(dirname "$0")/.." && pwd -P)
project="$repo/Benzo/Benzo.xcodeproj"
archive="$scratch/Benzo.xcarchive"
export_path="$scratch/export"
app="$export_path/Benzo.app"

build_args=(-project "$project" -scheme Benzo -configuration Release
    -derivedDataPath "$scratch/DerivedData" 'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO)
[[ -z "$build_number" ]] || build_args+=("CURRENT_PROJECT_VERSION=$build_number")
xcodebuild "${build_args[@]}" -showBuildSettings -json > "$output/build-settings.json"
setting() { plutil -extract "0.buildSettings.$1" raw -o - "$output/build-settings.json"; }
[[ "$(setting TARGET_NAME)" == Benzo ]] || fail 'Unexpected build settings target'
version=$(setting MARKETING_VERSION)
[[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || fail 'Marketing version must be an unambiguous three-part numeric version'
effective_build=$(setting CURRENT_PROJECT_VERSION)
[[ "$effective_build" =~ ^[1-9][0-9]*$ ]] || fail 'Effective build number must be a positive integer'
[[ -z "$build_number" || "$build_number" == "$effective_build" ]] || fail 'Build number override was not applied'
build_args+=("MARKETING_VERSION=$version" "CURRENT_PROJECT_VERSION=$effective_build")

if [[ "$mode" == developer-id ]]; then
    security find-identity -v -p codesigning > "$scratch/identities.txt"
    awk -v cert="$identity" -v team="$team" '
        $2 == cert && index($0, "\"Developer ID Application: ") && index($0, "(" team ")\"") { found=1 }
        END { exit !found }
    ' "$scratch/identities.txt" || fail 'Selected valid Developer ID Application identity/team was not found'
    build_args+=(CODE_SIGN_STYLE=Manual "DEVELOPMENT_TEAM=$team"
        "CODE_SIGN_IDENTITY=$identity" ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS=--timestamp)
else
    build_args+=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO)
fi
printf 'Archiving Benzo %s (%s), mode %s\n' "$version" "$effective_build" "$mode"
xcodebuild "${build_args[@]}" -archivePath "$archive" archive > "$output/archive.log" 2>&1
mkdir "$export_path"
if [[ "$mode" == developer-id ]]; then
    cat > "$scratch/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>developer-id</string>
<key>destination</key><string>export</string>
<key>signingStyle</key><string>manual</string>
<key>teamID</key><string>$team</string>
<key>signingCertificate</key><string>$identity</string>
</dict></plist>
PLIST
    xcodebuild -exportArchive -archivePath "$archive" -exportPath "$export_path" \
        -exportOptionsPlist "$scratch/ExportOptions.plist" > "$output/export.log" 2>&1
else
    ditto "$archive/Products/Applications/Benzo.app" "$app"
    # Signature resources ship inside the public app. The parent creates the log
    # with its private umask; only the signing subprocess uses public file modes.
    (umask 022; codesign --force --sign - "$app") > "$output/sign.log" 2>&1
fi

[[ -d "$app" && ! -L "$app" ]] || fail 'Expected exported app is missing'
info="$app/Contents/Info.plist"
plist() { plutil -extract "$1" raw -o - "$info"; }
[[ "$(plist CFBundleIdentifier)" == com.benzo.app ]] || fail 'Unexpected bundle identifier'
[[ "$(plist CFBundleShortVersionString)" == "$version" ]] || fail 'Exported marketing version mismatch'
[[ "$(plist CFBundleVersion)" == "$effective_build" ]] || fail 'Exported build number mismatch'
[[ "$(plist CFBundleExecutable)" == Benzo ]] || fail 'Unexpected bundle executable'
executable="$app/Contents/MacOS/Benzo"
[[ -f "$executable" && ! -L "$executable" ]] || fail 'Expected app executable is missing'
archs=$(lipo -archs "$executable")
[[ "$archs" == 'arm64 x86_64' || "$archs" == 'x86_64 arm64' ]] || fail 'Exported app must contain exactly arm64 and x86_64'
codesign --verify --deep --strict --all-architectures "$app" > "$output/verify-app.log" 2>&1
for arch in arm64 x86_64; do
    signature="$output/signature-$arch.txt"
    codesign -dv --verbose=4 --arch "$arch" "$app" > "$signature" 2>&1
    if [[ "$mode" == developer-id ]]; then
        grep -q '^Authority=Developer ID Application:' "$signature" || fail 'App lacks a Developer ID signature'
        grep -qx "TeamIdentifier=$team" "$signature" || fail 'App signing team mismatch'
        grep -Eq '^CodeDirectory .*flags=.*\(.*runtime.*\)' "$signature" || fail 'App hardened runtime is missing'
        grep -q '^Timestamp=' "$signature" || fail 'App secure timestamp is missing'
    else
        grep -qx 'Signature=adhoc' "$signature" || fail 'Community app is not explicitly ad-hoc signed'
    fi
done

# Usage: notarize_and_staple <submission> <staple-target> <evidence-name>
notarize_and_staple() {
    local receipt="$output/notary-$3.json" staple_log="$output/staple-$3.log" status
    xcrun notarytool submit "$1" --keychain-profile "$profile" --wait \
        --output-format json > "$receipt"
    status=$(plutil -extract status raw -o - "$receipt")
    [[ "$status" == Accepted ]] || fail 'Apple notarization did not return Accepted'
    xcrun stapler staple "$2" > "$staple_log" 2>&1
    xcrun stapler validate "$2" >> "$staple_log" 2>&1
}
if [[ "$mode" == developer-id ]]; then
    ditto -c -k --keepParent "$app" "$scratch/Benzo.zip"
    notarize_and_staple "$scratch/Benzo.zip" "$app" app
    codesign --verify --deep --strict --all-architectures "$app" >> "$output/verify-app.log" 2>&1
    spctl --assess --type execute --verbose=4 "$app" > "$output/assess-app.log" 2>&1
fi

dmg_name="Benzo-$version.dmg"
dmg="$scratch/$dmg_name"
# hdiutil carries this directory's mode into the image root. Keep scratch/logs
# private while making the mounted distribution readable by other accounts.
mkdir -m 755 "$scratch/dmg-root"
ditto "$app" "$scratch/dmg-root/Benzo.app"
hdiutil create -volname Benzo -srcfolder "$scratch/dmg-root" -format UDZO "$dmg" > "$output/dmg.log" 2>&1
hdiutil verify "$dmg" >> "$output/dmg.log" 2>&1
if [[ "$mode" == developer-id ]]; then
    codesign --sign "$identity" --timestamp "$dmg" > "$output/sign-dmg.log" 2>&1
    codesign --verify --strict "$dmg" > "$output/verify-dmg.log" 2>&1
    notarize_and_staple "$dmg" "$dmg" dmg
    codesign --verify --strict "$dmg" >> "$output/verify-dmg.log" 2>&1
    spctl --assess --type open --context context:primary-signature --verbose=4 "$dmg" > "$output/assess-dmg.log" 2>&1
    trust='Developer ID signed; Apple notarization Accepted; app and DMG staples validated'
else
    trust='Ad-hoc signed app; unnotarized community artifact; no Gatekeeper acceptance claimed'
fi
checksum=$(shasum -a 256 "$dmg")
checksum=${checksum%% *}
[[ "$checksum" =~ ^[a-f0-9]{64}$ ]] || fail 'Invalid SHA256 result'
printf '%s  %s\n' "$checksum" "$dmg_name" > "$output/SHA256SUMS"
printf 'Mode: %s\nVersion: %s\nBuild: %s\nArchitectures: %s\nTrust: %s\n' \
    "$mode" "$version" "$effective_build" "$archs" "$trust" > "$output/artifact.txt"
mv "$dmg" "$output/$dmg_name"
rm "$output/INCOMPLETE"
printf 'Artifact: %s/%s\nSHA256: %s\n%s\n' "$output" "$dmg_name" "$checksum" "$trust"
