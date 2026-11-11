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

Benzo lives in your menubar. Choose settings before activation. Applying them
changes selected sleep and wake values system-wide, across power sources, through
`pmset -a`. The current source manages seven keys, including `womp` for network
wake; the values written depend on your selections. See the
[setting definitions](Benzo/Benzo/Models/SleepSetting.swift).

Toggling off or quitting attempts to restore the saved original values. That can
fail; keep the backup and seek recovery help if the outcome is uncertain.

See the [privacy notes](PRIVACY.md) for
what Benzo stores on your Mac and what the website does.

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

## Checking for updates in this source revision

The normal popover footer has **Check for Updates…**. It makes one bounded,
anonymous GitHub request on click and compares the app's bundle version with the
latest published stable release. **View Release** is a separate action that opens
the official page in your browser. There are no background checks, downloads,
installation, automatic quit or relaunch. The browser demo simulates the check
without contacting GitHub or opening another page.
Leaving the normal panel clears the result. Reopening it never starts a check;
use **Check for Updates** again for a fresh result.

The check requires a published stable tag and matching uploaded DMG; it does not
verify the artifact's authenticity, OS/architecture compatibility or installation
readiness. An unavailable check never means up to date. Local development or
prerelease versions that cannot be compared offer the Releases page instead.

Checking is safe during active or unresolved work because it never touches
settings or recovery. **Replacing the app is a separate operation:** resolve
recovery and verify safe quit first. An Off label is insufficient; preserve
preferences, saved originals, journals/fences and legacy grant evidence. Uncertain
legacy recovery needs explicit support. The existing native release hold remains.

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

## Landing page

[benzo.work](https://benzo.work/) — built with React/Vite, includes an interactive demo of unreleased app changes.

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

The `build` workflow runs web tests/build and full-Xcode Debug/Release/core tests.
The separate `security` workflow retains npm audit and Gitleaks. Neither workflow
publishes artifacts. The connected Vercel Git integration can deploy previews on
branch pushes and the site on main; inspect and authorize deployment before push.

The accepted delivery order is 03 → 01 → 04 → conditional 02 in the
[remediation plan](documentation/planning/tech_debt/benzo-remediation_2026-11-02/00_TECH_DEBT.md).
Older reorientation plans and their run log remain historical safety references.

## License

Benzo is licensed under the [MIT License](LICENSE). Third-party dependencies remain
under their own licenses.

## Security

To report a vulnerability, follow the [security policy](SECURITY.md). Send private
reports to contact@benzo.work; do not open a public issue for a suspected
vulnerability.
