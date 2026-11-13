#!/bin/bash
# Apple/privileged tools are synthetic. No real build/sign/notary/mount is used.
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd -P)
task=$(mktemp -d "${TMPDIR:-/tmp}/benzo-packaging-test.XXXXXX")
trap 'rm -rf -- "$task"' EXIT
mkdir "$task/bin"
fixture_python=$(command -v python3)
[[ ! -x /usr/bin/python3 ]] || fixture_python=/usr/bin/python3
ln -s "$fixture_python" "$task/bin/python3"
for tool in awk basename cat chmod dirname grep ln mkdir mktemp mv rm shasum tr; do
    ln -s "$(command -v "$tool")" "$task/bin/$tool"
done
for tool in uname xcodebuild git security ditto lipo codesign xcrun hdiutil spctl; do
    ln -s "$repo/scripts/tests/fixtures/packaging-tool.py" "$task/bin/$tool"
done
for tool in pmset sudo osascript kill launchctl open; do
    printf '#!/bin/bash\nexit 99\n' > "$task/bin/$tool"
    chmod +x "$task/bin/$tool"
done
count=0
check() { "$@" || { printf 'FAIL: %s\n' "$*" >&2; exit 1; }; }
run_case() {
    local name=$1 mode=$2 scenario=$3 expected=$4
    shift 4
    case_dir="$task/$name"
    mkdir "$case_dir"
    local signing=() result=0 suffix=-development
    if [[ "$mode" == developer-id ]]; then
        signing=(--signing-identity AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA --team-id TEAM123456)
        suffix=-signed-unnotarized
    fi
    local explicit_notary=false arg
    for arg in "$@"; do [[ "$arg" != --notarize ]] || explicit_notary=true; done
    [[ "$explicit_notary" == false ]] || suffix=
    PATH="$task/bin" BENZO_FIXTURE_LOG="$case_dir/argv.log" BENZO_FIXTURE_SCENARIO="$scenario" BENZO_FIXTURE_MODE="$mode" \
        APPLE_ID=SECRET-MUST-NOT-APPEAR APP_PASSWORD=SECRET-MUST-NOT-APPEAR \
        /bin/bash "$repo/scripts/build-dmg.sh" --mode "$mode" --output-dir "$case_dir/output" \
        ${signing[@]+"${signing[@]}"} "$@" > "$case_dir/result.log" 2>&1 || result=$?
    if [[ "$expected" == success ]]; then
        if [[ $result != 0 ]]; then cat "$case_dir/result.log"; check false; fi
        check test -f "$case_dir/output/Benzo-0.3.0$suffix.dmg"
        check test ! -e "$case_dir/output/INCOMPLETE"
        (cd "$case_dir/output" && shasum -a 256 -c SHA256SUMS) >/dev/null
    else
        check test "$result" -ne 0
        if [[ -d "$case_dir/output" ]]; then check test -f "$case_dir/output/INCOMPLETE"; fi
    fi
    if compgen -G "$case_dir/output/.work.*" >/dev/null; then check false; fi
    if grep -R -q 'SECRET-MUST-NOT-APPEAR' "$case_dir"; then check false; fi
    if [[ "$explicit_notary" == false && -f "$case_dir/argv.log" ]] && grep -Eq '^(xcrun|spctl)' "$case_dir/argv.log"; then check false; fi
    count=$((count+1)); printf 'PASS %s\n' "$name"
}
run_case development development success success --build-number 7
check grep -q 'FUNCTIONAL ACCOUNT-FREE BUILD' "$case_dir/output/artifact.txt"
if grep -q '^security' "$case_dir/argv.log"; then check false; fi
"$fixture_python" - "$case_dir/argv.log" <<'PY'
import sys
commands = [line for line in open(sys.argv[1]) if line.startswith('codesign\t') and '\t--sign\t' in line]
assert len(commands) == 2 and '--identifier\tcom.chrisrogers37.benzo-command' in commands[0] and '--identifier\tcom.benzo.app' in commands[1]
assert all('\t--sign\t-\t' in line and '--timestamp=none' in line for line in commands)
assert all('--entitlements' not in line and '--options\truntime' in line for line in commands)
PY
PATH="$task/bin" BENZO_FIXTURE_LOG="$case_dir/argv.log" /bin/bash "$repo/scripts/tests/validate-development-dmg.sh" "$case_dir/output" > "$case_dir/mount.log" 2>&1 || { cat "$case_dir/mount.log"; exit 1; }
check test -f "$case_dir/output/mounted-validation.txt"
check test ! -e "$case_dir/output/MOUNT_VALIDATION_INCOMPLETE"
if PATH="$task/bin" BENZO_FIXTURE_LOG="$case_dir/argv.log" BENZO_FIXTURE_SCENARIO=mounted-command-missing \
    /bin/bash "$repo/scripts/tests/validate-development-dmg.sh" "$case_dir/output" > "$case_dir/bad-mount.log" 2>&1; then check false; fi
check test "$(grep -c '^hdiutil.*detach' "$case_dir/argv.log")" -eq 2
check test -f "$case_dir/output/MOUNT_VALIDATION_INCOMPLETE"
check test ! -e "$case_dir/output/mounted-validation.txt"
count=$((count+2))
mkdir "$task/mount-tmp"
ln -s "$task/mount-tmp" "$task/mount-tmp-alias"
PATH="$task/bin" TMPDIR="$task/mount-tmp-alias" BENZO_FIXTURE_LOG="$case_dir/argv.log" \
    /bin/bash "$repo/scripts/tests/validate-development-dmg.sh" "$case_dir/output" > "$case_dir/canonical-mount.log" 2>&1 || { cat "$case_dir/canonical-mount.log"; exit 1; }
check test -f "$case_dir/output/mounted-validation.txt"
count=$((count+1))
for scenario in mounted-wrong-path mounted-duplicate mounted-extra mounted-missing; do
    if PATH="$task/bin" BENZO_FIXTURE_LOG="$case_dir/argv.log" BENZO_FIXTURE_SCENARIO="$scenario" \
        /bin/bash "$repo/scripts/tests/validate-development-dmg.sh" "$case_dir/output" > "$case_dir/$scenario.log" 2>&1; then check false; fi
    check grep -q 'Unexpected mount result' "$case_dir/$scenario.log"
    check test -s "$case_dir/output/mounted-attachment.plist"
    check test -f "$case_dir/output/mounted-attachment.log"
    check test -f "$case_dir/output/MOUNT_VALIDATION_INCOMPLETE"
    check test ! -e "$case_dir/output/mounted-validation.txt"
    count=$((count+1))
done
"$fixture_python" - "$case_dir/argv.log" <<'PY'
import sys
expected = None
for line in open(sys.argv[1]):
    args = line.rstrip('\n').split('\t')
    if args[:2] == ['hdiutil', 'attach']:
        expected = args[args.index('-mountpoint') + 1]
    elif args[:2] == ['hdiutil', 'detach']:
        assert args[2:] == [expected], 'Detach must use only the requested task-owned mountpoint'
PY
run_case signed developer-id success success
check grep -q 'not notarized' "$case_dir/output/artifact.txt"
run_case notarized developer-id success success --notarize --notary-profile benzo-fixture
check test "$(grep -c 'notarytool.*submit' "$case_dir/argv.log")" -eq 2
check test "$(grep -c 'notarytool.*log' "$case_dir/argv.log")" -eq 2
check test "$(grep -c 'stapler.*validate' "$case_dir/argv.log")" -eq 2
run_case dirty-source development dirty-source success
check grep -qx 'Source tree: dirty' "$case_dir/output/artifact.txt"
run_case empty-entitlements-plist development empty-entitlements-plist success
for scenario in git-status-failure invalid-version ambiguous-version duplicate-target bundle-version bundle-build bundle-id missing-slice command-missing-slice command-missing command-symlink bundled-daemon linked-daemon extra-executable nested-code wrong-command-id extra-entitlement malformed-entitlements bad-signature sign-failure archive-failure dmg-invalid; do
    run_case "$scenario" development "$scenario" failure
done
for component in app command; do
    for arch in arm64 x86_64; do
        scenario="$component-signature-invalid-$arch"
        run_case "$scenario" development "$scenario" failure
    done
done
run_case developer-unexpected-entitlement developer-id extra-entitlement failure
run_case developer-invalid-command developer-id command-signature-invalid-x86_64 failure
for scenario in identity-missing wrong-team no-runtime no-timestamp; do
    run_case "$scenario" developer-id "$scenario" failure
done
for scenario in notary-failure notary-rejected notary-rejected-command notary-log-failure dmg-rejected staple-failure staple-invalid assessment-failure; do
    run_case "$scenario" developer-id "$scenario" failure --notarize --notary-profile benzo-fixture
    if [[ "$scenario" == notary-rejected-command ]]; then check test -f "$case_dir/output/notary-app-log.json"; fi
done
run_case bad-build development success failure --build-number 0
run_case ignored-build-override development success failure --build-number 8
run_case development-notary development success failure --notarize --notary-profile forbidden
run_case profile-without-consent developer-id success failure --notary-profile forbidden
run_case notary-without-profile developer-id success failure --notarize
run_case xcode-split development xcode-split success
run_case xcode-malformed development xcode-malformed failure
run_case xcode-failure development xcode-failure failure

# Invalid arguments/output cannot call build tools or erase pre-existing paths.
reject() {
    if PATH="$task/bin" BENZO_FIXTURE_LOG="$task/rejected-argv.log" /bin/bash "$repo/scripts/build-dmg.sh" "$@" > "$task/rejection.log" 2>&1; then check false; fi
    count=$((count+1))
}
mkdir "$task/existing"
printf preserve > "$task/existing/sentinel"
ln -s "$task/existing" "$task/link"
for output in "$task/existing" "$task/link" "$task/missing/child" relative "$task/new/"; do
    reject --mode development --output-dir "$output"
done
check test -f "$task/existing/sentinel"
check test -L "$task/link"
reject --output-dir "$task/no-mode"
reject --mode community --output-dir "$task/old-mode"
reject --mode developer-id --output-dir "$task/no-identity"
reject --mode development --mode development --output-dir "$task/duplicate"
reject --mode development --output-dir
reject --mode developer-id --signing-identity AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA --team-id TEAM123456 --notarize --notarize --output-dir "$task/duplicate-notary"
check test ! -e "$task/rejected-argv.log"
printf 'stale success\n' > "$task/development/output/mounted-validation.txt"
printf 'changed image\n' >> "$task/development/output/Benzo-0.3.0-development.dmg"
if PATH="$task/bin" BENZO_FIXTURE_LOG="$task/development/argv.log" /bin/bash "$repo/scripts/tests/validate-development-dmg.sh" "$task/development/output" > "$task/checksum-failure.log" 2>&1; then check false; fi
check test -f "$task/development/output/MOUNT_VALIDATION_INCOMPLETE"
check test ! -e "$task/development/output/mounted-validation.txt"
count=$((count+1))
printf 'PASS %s packaging checks (Apple/host tools stubbed)\n' "$count"
