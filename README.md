# Benzo

**The anti-[Amphetamine](https://apps.apple.com/us/app/amphetamine/id937984704?mt=12) for macOS.** Sleep settings in your menu bar.

Benzo adjusts selected `pmset` sleep and wake settings. A configured value does not prove physical hibernation, USB power behavior or battery savings on a particular Mac.

## Source containment work

This source revision removes timed sleep, blocker termination, automatic drift
reapplication and launch-time permission installation. Sleep Now is unavailable
while recovery controls are being updated. Choose options before activation;
settings stay frozen while active or original-settings evidence is present or
cannot be inspected, including after the legacy Restore/Off action.

Manual activation, restoration and quit still have known recovery defects. An Off
label is not proof of restored settings. This is an intermediate source change,
not a safe native release. Existing release downloads have not been replaced by
this work. See the [remediation plan](documentation/planning/tech_debt/benzo-remediation_2026-11-02/00_TECH_DEBT.md).

The current source also removes permission installation and repair. Its permission
panel only observes metadata for the legacy rule: absent, present but unverified,
or unknown. Refresh and Back never authorize an operation or change permissions.
Existing downloads still use their older setup flow.

## Install

**Download** the latest `.dmg` from [Releases](https://github.com/chrisrogers37/benzo/releases).

Since Benzo isn't notarized yet, macOS will block it on first launch. Either:
- Right-click the app → **Open**
- Or run: `xattr -d com.apple.quarantine /Applications/Benzo.app`

**Homebrew** (personal tap):
```
brew tap chrisrogers37/benzo
brew install --cask benzo
```

## What it does

Benzo lives in your menubar. Toggle it on and it applies six `pmset` commands that Apple should have put in System Settings years ago:

```
sudo pmset -a hibernatemode 25
sudo pmset -a powernap 0
sudo pmset -a standby 0
sudo pmset -a autopoweroff 0
sudo pmset -a tcpkeepalive 0
sudo pmset -a proximitywake 0
```

Toggling off or quitting attempts to restore the saved original values. That can
fail; keep the backup and seek recovery help if the outcome is uncertain.

### Features

- **Configuration choices** — choose sleep and wake settings before activation
- **Conservative selection lock** — active sessions or retained recovery evidence prevent editing
- **Saved originals** — legacy deactivate, Restore and quit attempt recovery, with unresolved failure paths
- **Sleep Now unavailable** — manual and timed sleep are disabled in this source revision
- **Diagnostics** — Option-click the menubar icon for existing sleep sessions, wake reasons, USB devices and settings observations; these do not prove recovery or hardware behavior

### Recovery and removal

Removing the app is not verified restoration or permission-rule retirement. The
cask no longer asks the app to quit or deletes its permission rule, backup or
preferences during removal/zap. Preserve `~/Library/Application Support/Benzo/`
and the existing grant until an explicit recovery/retirement flow resolves them.
Do not delete an invalid or unreadable backup to reactivate the app. Seek help
through [GitHub issues](https://github.com/chrisrogers37/benzo/issues).

## Requirements

- macOS Ventura (13.0) or later
- Intel or Apple Silicon
- Admin privileges (one-time setup installs a sudoers rule for passwordless `pmset`)

## Build from source

Native builds require macOS and full Xcode; Command Line Tools alone cannot build
the project or its XCTest bundle. These commands compile the app without launching
it, then run the unhosted core tests with injected fakes:

```sh
export BENZO_TEST_DERIVED="$(mktemp -d "${TMPDIR:-/tmp}/benzo-derived.XXXXXX")"
xcodebuild -version
xcodebuild -project Benzo/Benzo.xcodeproj -scheme Benzo -configuration Debug -derivedDataPath "$BENZO_TEST_DERIVED" CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Benzo/Benzo.xcodeproj -scheme Benzo -configuration Release -derivedDataPath "$BENZO_TEST_DERIVED" CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Benzo/Benzo.xcodeproj -scheme BenzoCoreTests -destination 'platform=macOS' -derivedDataPath "$BENZO_TEST_DERIVED" CODE_SIGNING_ALLOWED=NO test
```

`BenzoCoreTests` does not host or launch the app. Its source list excludes the live
command and login adapters. DiagnosticService receives fake reader outcomes. Tests
use in-memory preferences, fake commands and clocks, and task-owned temporary
backup files. Do not run the
production app or privileged/lifecycle acceptance on an always-on fleet host.
Physical sleep, permissions and recovery acceptance require a separately approved
test Mac; a successful build or fake-based test does not prove those outcomes.

The `build` workflow's native job also archives a universal Release app with
distribution signing disabled (`CODE_SIGNING_ALLOWED=NO`). After
the tests pass, it checks the archive's bundle identifier, version, build number and
arm64/x86_64 slices, then uploads `benzo-ci-build-evidence` (a tar.gz of the
`.xcarchive`, `benzo-ci-manifest.txt` and `SHA256SUMS`) for 7 days. This is build
evidence for inspection only: it is not distribution signing, notarization, a
release candidate or native acceptance.

### Package a native artifact

The selected release path is an explicitly **unnotarized community build** on
GitHub Releases. No Developer ID is available. The app uses an ad-hoc signature;
this does not establish a Developer ID identity, Apple notarization, or Gatekeeper
acceptance. Apple Developer membership is not a prerequisite for this selected path.

After its native tests and archive checks pass, the existing `build` workflow
runs the packaging script in community mode on its full-Xcode runner. It uploads
only the DMG, `SHA256SUMS` and `artifact.txt` as `benzo-community-candidate`, retained
for 7 days. The candidate keeps the checked-out native project's version and build
number. This prepares inspectable bytes; it does not publish a GitHub Release.
Final version/build allocation, artifact acceptance, and approved native recovery,
restore and quit acceptance still precede publication.

`scripts/build-dmg.sh` requires an explicit distribution mode, full Xcode, and a
new absolute output directory whose parent already exists. It never reuses or
deletes a shared `build/` directory. Choose a positive release build number;
`MARKETING_VERSION` in the native project remains the app version authority.
The site's private npm version is independent metadata.

```sh
# Explicitly ad-hoc signed and unnotarized; no Gatekeeper acceptance claimed.
./scripts/build-dmg.sh --mode community --output-dir "$HOME/Benzo-community-candidate" --build-number 2

# Safe packaging regression checks: all Apple and host tools are stubbed.
bash scripts/tests/build-dmg-test.sh
```

Both modes verify the app's actual version/build, arm64 and x86_64 slices, and
signatures. Successful output includes `artifact.txt`, `SHA256SUMS`, and the
verified DMG; failed runs
retain logs and an `INCOMPLETE` marker without a distributable DMG. The script
does not publish a release. Real artifact checks and approved native recovery,
restore and quit acceptance remain required before publication; fixture success
and a website deployment do not complete those gates.

### Future Developer ID distribution

Revisit Developer ID signing and notarization when broader distribution or support
needs justify the Apple Developer setup. It is a future target, not the current
release mode or a blocker for the community release. The existing script already
has an explicit mode for that work; no updater or release platform is required.

On the selected signing Mac, install a valid Developer ID Application certificate
and configure a `notarytool` keychain profile securely. Then use the certificate's
SHA1 and team ID with that profile; never put passwords or private keys in chat,
repository files, or CLI arguments:

```sh
# Future use only: uploads the app ZIP and DMG to Apple.
./scripts/build-dmg.sh --mode developer-id --output-dir "$HOME/Benzo-signed-candidate" --build-number 2 \
  --signing-identity '<40-character-certificate-SHA1>' --team-id '<10-character-team-ID>' \
  --notary-profile '<configured-profile-name>'
```

That path requires the real artifact's Developer ID signature and hardened
runtime, Apple's Accepted results, validated app and DMG staples, Gatekeeper
assessment, and approved clean-Mac installation/launch acceptance before claiming
signed/notarized distribution. Any signing, export, notarization, stapling or
assessment error fails the build; it never silently downgrades to community mode.

## Landing page

[benzo-gules.vercel.app](https://benzo-gules.vercel.app) — built with React/Vite, includes an interactive mockup of the app.

Use Node 24 LTS (24.15.0 or newer in the 24.x line); `.nvmrc` pins the version used
in CI. With nvm installed, run `nvm install` and `nvm use` first.

```sh
npm ci
npm test
npm run build
npm audit --audit-level=moderate
npm run dev
```

`npm test` runs Vitest, React Testing Library and jsdom interaction tests.
`src/landing/BenzoLanding.jsx` owns one `src/demo/useBenzoDemo.js` state and passes
it to `src/landing/NativeAppDemo.jsx`; `src/design/appPresentation.js` owns its
native presentation reference. Native UI changes must match this active demo.
Unbundled `BenzoHybrid`, `BenzoMockup` and their historical tests remain unchanged.

The read runner has bounded time and output, with separate stdout/stderr capture.
Its tests may execute only an owned synthetic child fixture. This narrow exception
does not permit production commands or demonstrate privileged-chain completion.
Legacy mutation transport remains synchronous and unreleased pending recovery work.

The `build` workflow runs web tests/build, full-Xcode Debug and Release
archive builds, and core tests. Its native job keeps the CI build evidence described
above and the unnotarized community candidate as separate short-lived workflow
artifacts. Neither publishes a release. The separate `security` workflow retains
npm audit and Gitleaks and publishes no artifacts. The connected Vercel Git
integration can deploy previews on branch pushes and the site on main; inspect and
authorize deployment before push.

The accepted delivery order is 03 → 01 → 04 → conditional 02 in the
[remediation plan](documentation/planning/tech_debt/benzo-remediation_2026-11-02/00_TECH_DEBT.md).
Older reorientation plans and their run log remain historical safety references.

## License

MIT
