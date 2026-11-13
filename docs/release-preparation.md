# Release preparation before paid enrollment

The development package exercises the same application and embedded helper source
as the future release. It does not grant helper access: Benzo deliberately requires
a Developer ID identity for both sides of its privileged connection. Automated
tests inject authorization, settings and storage boundaries instead of relaxing
that production rule. Developing the code, building the bundle, inspecting the
DMG and running those tests do not require paid Apple enrollment.

The integration carries the implementation from packaging PR #102 (`6d79e66`),
manual updater PR #103 (`a6859ac`) and accessibility PR #105 (`a0b2184`) onto the
account-helper/recovery checkpoint `4f40b3b` in PR #104. Their original branches
remain intact; passing checks on those separate branches do not validate the
combined artifact. This guide is the current pre-enrollment delivery boundary.

## Build and inspect without credentials

Use macOS with full Xcode and the Node version in `.nvmrc`. Follow the Debug,
Release and core-test commands in [README](../README.md#build-from-source), then:

```sh
# Choose a new absolute directory whose parent already exists.
./scripts/build-dmg.sh --mode development --output-dir /absolute/new/benzo-development
```

The DMG contains `Benzo Development.app`, an Applications shortcut and development
instructions. Its distinct filename avoids replacing an installed `Benzo.app`
through an ordinary drag and drop. It retains the production bundle identifier
and data locations; it is not a separate sandbox. Do not run it alongside another
Benzo instance or use it to recover an active session requiring privileged writes.
Gatekeeper may block a transferred development build; use a local development
build on an approved test Mac rather than disabling security protections.

The package is ad-hoc signed and unnotarized. It cannot set up the helper or change
power settings. It supports inspection of the interface, diagnostics and manual
update checker, subject to the host's normal permissions. Building and mounting
the package does not launch the app, register a service or install it.

CI runs full-Xcode builds, unhosted XCTest, web tests/build, packaging failure
fixtures and real development-DMG construction/inspection. Security checks cover
the dependency audit and secret scan. Download the CI artifact before its seven-day
expiration; check `SHA256SUMS` and its source manifest. A CI artifact is not a
published release or proof that live administrator authorization works.
Artifact names include the run attempt so retrying a failed job preserves prior
evidence without an upload-name collision.

## Prepare signing without uploading

When the publisher later has Apple Developer membership and a valid Developer ID
Application certificate/private key, build the signed package explicitly:

```sh
./scripts/build-dmg.sh --mode developer-id \
  --output-dir /absolute/new/benzo-signed \
  --signing-identity CERTIFICATE_SHA1 --team-id TEAM_ID
```

Replace the placeholders with the selected identity's 40 hexadecimal characters
and 10-character team identifier. No certificate, password or private key belongs
in the repository. The script verifies app/helper identities, signed Info.plist
role markers, absence of unexpected entitlements, both architectures, hardened
runtime and secure timestamps. Signing alone does
not upload the artifact, notarize it or publish a release.

This intermediate signed package is for inspection, not proof that macOS will
approve its daemon. Apple's ServiceManagement requirements include notarization
for apps containing LaunchDaemons; the final permission test uses the notarized
artifact, with real macOS approval and account authorization.

Application-specific roles use the signed `BenzoHelperRole` Info.plist key;
the standalone helper embeds its plist in the executable. They are not custom
entitlements. A native development launch exposed AMFI rejection of the earlier
invented entitlement keys despite successful on-disk signature verification.
The certificate, team, identifier and role requirements remain mandatory for
privileged communication. Apple's [code requirement language](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/RequirementLang/RequirementLang.html)
supports these signed Info.plist predicates.

An individual membership is sufficient; Benzo's users do not need membership.
The exact signing/notarization path cannot be accepted using stubbed tools or an
ad-hoc package. Current requirements: [Developer ID](https://developer.apple.com/developer-id/)
and [Apple's notarization protections](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## Explicit notarization, later

Configure a notarytool Keychain profile interactively on the release machine.
Keep credentials in Keychain, not command history, environment files or CI logs.
Only an explicit upload request adds these arguments to the signed build:

```sh
./scripts/build-dmg.sh --mode developer-id \
  --output-dir /absolute/new/benzo-notarized \
  --signing-identity CERTIFICATE_SHA1 --team-id TEAM_ID \
  --notarize --notary-profile benzo-notary
```

Require Apple's Accepted response, inspect the notary log for warnings, validate
the stapled app and DMG and run Gatekeeper assessment. Do not distribute partial
output marked `INCOMPLETE`. See [Apple's command-line workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

## Final signed-artifact acceptance

These are pending tests, not completed by the development build:

- Record exact source commit, version/build, app/DMG checksums, macOS and hardware.
  Install the notarized DMG on an approved test Mac, including a fresh-account
  case; verify Gatekeeper without removing quarantine.
- Exercise first launch from the DMG, then from Applications, duplicate copies,
  an upgrade from the existing release and a different installing account. Follow
  the app's setup guidance and verify service location before removing/ejecting
  any old bundle. Registration/replacement reject read-only volumes using the
  public volume property and ask the user to move the app to Applications. This
  does not prove all relocation cases. See [Apple's packaging test scenarios](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution).
- Approve the bundled helper, then separately authorize the setup account. Check
  denied/cancelled approval, stale or missing helper, and another local account.
  Confirm a renamed/recreated account cannot inherit the grant through UID reuse.
- Capture a baseline; apply only supported selected settings, independently read
  them back, restore and verify the full baseline. Exercise quit restoration,
  denial/failure, Retry/Stay Open/Quit Anyway, relaunch and lost replies. Never
  equate configuration readback with physical sleep or USB power behavior.
- Check revocation, approved reboot persistence and helper replacement/removal.
  Unresolved sessions must block lifecycle changes; failures must preserve
  evidence and never trigger an automatic replay or account transfer.
- Exercise the combined interface using keyboard and spoken VoiceOver, menu-bar
  entry/return, Reduce Motion, larger supported display/text and constrained
  placement. Check update result → release page → close/reopen with stale results
  cleared. Browser parity is separate evidence from native accessibility.
- From resolved Off, confirm Remove Helper, wait for successful removal, quit,
  and remove the app. Reinstall and verify ownership/evidence are retained.

Only then allocate the public version/build, create and inspect its final artifact,
publish accepted release assets and update the cask with the actual DMG checksum.
If version/build changes after acceptance, recheck the final artifact. There is no
automatic installer in this release; Check for Updates links to the release page.

## Before the planned factory reset

Verify source commits are on the remote and release assets are downloaded and
checksummed outside this Mac. Copy this runbook and the chosen local acceptance
evidence to the owner's backup destination. A Git push does not back up local
Documents files or a signing private key. Export any signing identity through
Keychain's protected export process to the owner's secure backup, separately from
source and evidence. Verify that backup before erasing the Mac. Factory reset,
credential creation and enrollment remain separate owner actions.
