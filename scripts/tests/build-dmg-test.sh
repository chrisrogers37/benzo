#!/bin/bash
# No real build/signing/disk-image/notary/host tools are available on the child PATH.
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd -P)
task=$(mktemp -d "${TMPDIR:-/tmp}/benzo-packaging-test.XXXXXX")
trap 'rm -rf -- "$task"' EXIT
mkdir "$task/bin"
for tool in awk basename cat cp dirname grep mkdir mktemp mv rm shasum stat tr; do
    ln -s "$(command -v "$tool")" "$task/bin/$tool"
done
for tool in uname xcodebuild plutil security ditto lipo codesign xcrun hdiutil spctl; do
    ln -s "$repo/scripts/tests/fixtures/packaging-tool.sh" "$task/bin/$tool"
done
# Explicit poison stubs protect against later accidental additions, too.
for tool in pmset sudo osascript kill launchctl; do
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
    local signing=()
    if [[ "$mode" == developer-id ]]; then
        signing=(--signing-identity AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA --team-id TEAM123456 --notary-profile benzo-fixture)
    fi
    local result=0
    PATH="$task/bin" BENZO_FIXTURE_LOG="$case_dir/argv.log" BENZO_FIXTURE_SCENARIO="$scenario" \
        BENZO_FIXTURE_MODE="$mode" BENZO_FIXTURE_EXPORT_OPTIONS="$case_dir/export-options.plist" \
        APP_PASSWORD='SECRET-MUST-NOT-APPEAR' APPLE_ID='SECRET-MUST-NOT-APPEAR' \
        /bin/bash "$repo/scripts/build-dmg.sh" --mode "$mode" --output-dir "$case_dir/output" \
        ${signing[@]+"${signing[@]}"} "$@" > "$case_dir/result.log" 2>&1 || result=$?
    if [[ "$expected" == success ]]; then
        if [[ $result -ne 0 ]]; then cat "$case_dir/result.log"; check false; fi
        check test -f "$case_dir/output/Benzo-0.3.0.dmg"
        check test ! -e "$case_dir/output/INCOMPLETE"
        (cd "$case_dir/output" && shasum -a 256 -c SHA256SUMS) >/dev/null
    else
        check test "$result" -ne 0
        check test ! -e "$case_dir/output/Benzo-0.3.0.dmg"
    fi
    if compgen -G "$case_dir/output/.work.*" >/dev/null; then check false; fi
    if grep -R -q 'SECRET-MUST-NOT-APPEAR' "$case_dir"; then check false; fi
    count=$((count+1))
    printf 'PASS %s\n' "$name"
}

run_case community community success success --build-number 7
check grep -q 'unnotarized community artifact' "$case_dir/output/artifact.txt"
if grep -Eq '^(xcrun|security|spctl)' "$case_dir/argv.log"; then check false; fi
check grep -q 'CODE_SIGNING_ALLOWED=NO' "$case_dir/argv.log"
check grep -q 'ARCHS=arm64 x86_64' "$case_dir/argv.log"
check grep -q 'ONLY_ACTIVE_ARCH=NO' "$case_dir/argv.log"

run_case developer developer-id success success --build-number 7
check grep -q '<string>developer-id</string>' "$case_dir/export-options.plist"
check grep -q 'ENABLE_HARDENED_RUNTIME=YES' "$case_dir/argv.log"
check grep -q 'notarytool.*Benzo.zip' "$case_dir/argv.log"
check grep -q 'notarytool.*Benzo-0.3.0.dmg' "$case_dir/argv.log"
check test "$(grep -c 'stapler.*validate' "$case_dir/argv.log")" -eq 2
check grep -q 'primary-signature' "$case_dir/argv.log"

for scenario in invalid-version ambiguous-version bundle-version bundle-build missing-slice bad-signature sign-failure archive-failure dmg-invalid; do
    run_case "$scenario" community "$scenario" failure
done
for scenario in identity-missing export-failure wrong-team no-runtime no-timestamp notary-failure notary-rejected dmg-rejected staple-failure staple-invalid assessment-failure; do
    run_case "$scenario" developer-id "$scenario" failure
    if grep -q 'codesign.*--sign.*	-	' "$case_dir/argv.log"; then check false; fi
done
run_case bad-build community success failure --build-number 0
run_case ignored-build-override community success failure --build-number 8
run_case contradictory-mode community success failure --notary-profile forbidden

# Argument/output rejections happen before any build tools run and never erase an
# existing output, a shared build folder, or a symlink target.
reject() {
    if PATH="$task/bin" BENZO_FIXTURE_LOG="$task/rejected-argv.log" /bin/bash "$repo/scripts/build-dmg.sh" "$@" > "$task/rejection.log" 2>&1; then
        printf 'FAIL: accepted %s\n' "$*" >&2; exit 1
    fi
    count=$((count+1))
}
mkdir "$task/existing" "$task/build"
printf 'preserve\n' > "$task/existing/sentinel"
printf 'preserve\n' > "$task/build/sentinel"
ln -s "$task/existing" "$task/link"
for output in "$task/existing" "$task/link" "$task/missing/child" relative "$task/new/"; do
    reject --mode community --output-dir "$output"
done
check test -f "$task/existing/sentinel"
check test -f "$task/build/sentinel"
check test -L "$task/link"
reject --output-dir "$task/no-mode"
reject --mode developer-id --output-dir "$task/no-identity"
reject --mode community --mode community --output-dir "$task/duplicate-mode"
reject --mode community --output-dir
check test ! -e "$task/duplicate-mode"
check test ! -e "$task/rejected-argv.log"
printf 'PASS %s packaging fixtures (Apple/host tools stubbed)\n' "$count"
