#!/bin/bash
# Synthetic filesystem/argv fixture only. Never delegates to an Apple tool.
set -euo pipefail
tool=${0##*/}
printf '%s' "$tool" >> "$BENZO_FIXTURE_LOG"
printf '\t%s' "$@" >> "$BENZO_FIXTURE_LOG"
printf '\n' >> "$BENZO_FIXTURE_LOG"
scenario=${BENZO_FIXTURE_SCENARIO:-success}
last=${!#}
has() { for arg in "${args[@]}"; do [[ "$arg" != "$1" ]] || return 0; done; return 1; }
value() {
    local previous= arg
    for arg in "${args[@]}"; do
        if [[ "$previous" == "$1" ]]; then printf '%s\n' "$arg"; return; fi
        previous=$arg
    done
    return 1
}
args=("$@")
make_app() (
    # Xcode's archived bundle is public; keep its enclosing scratch private.
    umask 022
    mkdir -p "$1/Contents/MacOS"
    printf 'fixture executable\n' > "$1/Contents/MacOS/Benzo"
    chmod 755 "$1/Contents/MacOS/Benzo"
    cat > "$1/Contents/Info.plist" <<INFO
CFBundleIdentifier=com.benzo.app
CFBundleShortVersionString=$([[ "$scenario" == bundle-version ]] && printf '0.2.0' || printf '0.3.0')
CFBundleVersion=$([[ "$scenario" == bundle-build ]] && printf '999' || printf '%s' "${BENZO_FIXTURE_BUILD:-7}")
CFBundleExecutable=Benzo
INFO
)
case "$tool" in
    uname) printf 'Darwin\n' ;;
    xcodebuild)
        if has -version; then printf 'Xcode 16.4\n'; exit 0; fi
        if has -showBuildSettings; then
            version=0.3.0
            [[ "$scenario" != invalid-version ]] || version='0.3.0/../../unsafe'
            [[ "$scenario" != ambiguous-version ]] || version=$'0.3.0\n0.4.0'
            printf '0.buildSettings.TARGET_NAME=Benzo\n0.buildSettings.MARKETING_VERSION=%s\n0.buildSettings.CURRENT_PROJECT_VERSION=%s\n' "$version" "${BENZO_FIXTURE_BUILD:-7}"
        elif has -exportArchive; then
            [[ "$scenario" != export-failure ]] || exit 42
            # Preserve the plist so tests can inspect the exact selected mode.
            cp "$(value -exportOptionsPlist)" "$BENZO_FIXTURE_EXPORT_OPTIONS"
            make_app "$(value -exportPath)/Benzo.app"
            printf 'must not enter DMG\n' > "$(value -exportPath)/Packaging.log"
        elif has archive; then
            [[ "$scenario" != archive-failure ]] || exit 42
            make_app "$(value -archivePath)/Products/Applications/Benzo.app"
        else exit 90; fi ;;
    plutil)
        [[ "$1" == -extract && "$3" == raw && "$4" == -o && "$5" == - ]] || exit 90
        # Preserve embedded newlines to exercise ambiguous settings rejection.
        if [[ "$scenario" == ambiguous-version && "$2" == 0.buildSettings.MARKETING_VERSION ]]; then
            printf '0.3.0\n0.4.0\n'; exit 0
        fi
        awk -v key="$2" 'index($0, key "=") == 1 { print substr($0, length(key)+2); found=1 } END {exit !found}' "$last" ;;
    security)
        [[ "$scenario" != identity-missing ]] || exit 0
        printf '  1) AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA "Developer ID Application: Fixture (TEAM123456)"\n' ;;
    ditto)
        if [[ "$1" == -c ]]; then
            [[ "$2" == -k && "$3" == --keepParent && "$4" == *.app && "$5" == *.zip ]] || exit 90
            printf 'fixture zip\n' > "$5"
        else cp -pR "$1" "$2"; fi ;;
    lipo) printf '%s\n' "$([[ "$scenario" == missing-slice ]] && printf arm64 || printf 'arm64 x86_64')" ;;
    codesign)
        if has --verify; then
            [[ "$scenario" != bad-signature ]] || exit 42
        elif has -dv; then
            if [[ "$BENZO_FIXTURE_MODE" == community ]]; then
                printf 'Signature=adhoc\n'
            else
                printf 'Authority=Developer ID Application: Fixture (TEAM123456)\n'
                printf 'TeamIdentifier=%s\n' "$([[ "$scenario" == wrong-team ]] && printf WRONG12345 || printf TEAM123456)"
                [[ "$scenario" == no-runtime ]] || printf 'CodeDirectory v=20500 size=123 flags=0x10000(runtime) hashes=1+1\n'
                [[ "$scenario" == no-timestamp ]] || printf 'Timestamp=Nov 4, 2026\n'
            fi
        elif has --sign; then
            [[ "$scenario" != sign-failure ]] || exit 42
            if [[ "$(value --sign)" == - && "$last" == *.app ]]; then
                mkdir -m 755 "$last/Contents/_CodeSignature"
                # Like codesign, this file inherits the signing process umask.
                printf 'fixture signature resource\n' > "$last/Contents/_CodeSignature/CodeResources"
            fi
        else exit 90; fi ;;
    xcrun)
        if [[ "$1" == notarytool && "$2" == submit ]]; then
            [[ "$3" == *.zip || "$3" == *.dmg ]] || exit 90
            [[ "$4" == --keychain-profile && "$5" == benzo-fixture && "$6" == --wait && "$7" == --output-format && "$8" == json ]] || exit 90
            [[ "$scenario" != notary-failure ]] || exit 42
            status=Accepted
            [[ "$scenario" != notary-rejected ]] || status=Invalid
            [[ "$scenario" != dmg-rejected || "$3" != *.dmg ]] || status=Invalid
            printf 'status=%s\nid=fixture\n' "$status"
        elif [[ "$1" == stapler ]]; then
            [[ "$scenario" != staple-failure || "$2" != staple ]] || exit 42
            [[ "$scenario" != staple-invalid || "$2" != validate ]] || exit 42
        else exit 90; fi ;;
    hdiutil)
        if [[ "$1" == create ]]; then
            root=$(value -srcfolder)
            [[ -d "$root/Benzo.app" && ! -e "$root/Packaging.log" ]] || exit 90
            [[ "$(stat -f '%Lp' "$root")" == 755 ]] || exit 90
            if [[ "$scenario" == signature-permissions ]]; then
                for directory in "$root/Benzo.app" "$root/Benzo.app/Contents" "$root/Benzo.app/Contents/MacOS" "$root/Benzo.app/Contents/_CodeSignature"; do
                    [[ "$(stat -f '%Lp' "$directory")" == 755 ]] || exit 90
                done
                [[ "$(stat -f '%Lp' "$root/Benzo.app/Contents/_CodeSignature/CodeResources")" == 644 ]] || exit 90
                [[ "$(stat -f '%Lp' "$root/Benzo.app/Contents/MacOS/Benzo")" == 755 ]] || exit 90
                scratch=$(dirname "$root")
                output=$(dirname "$scratch")
                [[ "$(stat -f '%Lp' "$scratch")" == 700 && "$(stat -f '%Lp' "$output")" == 700 ]] || exit 90
                for log in "$output/sign.log" "$output/archive.log" "$output/dmg.log"; do
                    [[ "$(stat -f '%Lp' "$log")" == 600 ]] || exit 90
                done
            fi
            printf 'fixture DMG\n' > "$last"
        elif [[ "$1" == verify ]]; then
            [[ "$scenario" != dmg-invalid ]] || exit 42
        else exit 90; fi ;;
    spctl) [[ "$scenario" != assessment-failure ]] || exit 42 ;;
    *) printf 'Unexpected fixture tool: %s\n' "$tool" >&2; exit 90 ;;
esac
