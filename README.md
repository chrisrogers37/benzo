# Benzo

**The anti-[Amphetamine](https://apps.apple.com/us/app/amphetamine/id937984704?mt=12) for macOS.** Sleep settings in your menu bar.

Benzo adjusts selected `pmset` sleep and wake settings. A configured value does not prove physical hibernation, USB power behavior or battery savings on a particular Mac.

## Current source status

The current source implements a manual apply-and-restore workflow. Choices are
editable only when no unresolved session or recovery evidence exists. Apply
captures the reported per-profile originals before writing exact selected
settings; applying freezes the selection. Switching Off, choosing **System
Defaults**, or quitting attempts to restore those captured values. System
Defaults does not reset macOS to Apple's factory defaults. Sleep Now remains
disabled. A successful settings readback confirms reported configuration only;
it does not prove physical sleep, hibernation, USB power behavior or battery
savings.

If a setting changes unexpectedly, recovery offers Keep Current, Restore
Recorded Original Anyway, or Defer while retaining the evidence. A same-boot
uncertain command blocks further writes even when a later read matches. A
verified later boot permits read-only reconciliation, never automatic replay or
restoration. If quit-time restoration fails, the app offers Retry, Stay Open or
Quit Anyway; Quit Anyway preserves recovery evidence. Legacy flat backups cannot
prove per-profile originals. Their recovery and any old permission-rule
retirement require administrator-assisted review outside the app; the app does
not install or remove that rule. These source changes have not completed native
acceptance or release, and the latest public release remains v0.3.0. See the
[remediation plan](documentation/planning/tech_debt/benzo-remediation_2026-11-02/00_TECH_DEBT.md)
and [recovery plan](documentation/planning/tech_debt/benzo-remediation_2026-11-02/02_recovery-engine.md).

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

Benzo lives in your menubar. It captures the available AC, battery and UPS
profiles, then applies only selected settings and profile/key values that are
reported and supported. Writes use macOS's administrator-authorized path;
prompt caching is managed by macOS. Readback checks reported values; hardware
sleep behavior is a separate outcome.

A setting is unavailable when any required key is absent from a reported
profile. Benzo disables that control and reports the missing profile/key; it
does not invent profiles or values.

### Features

- **Manual settings** — choose available settings before applying; selections freeze for the session
- **Captured originals** — Off, System Defaults and quit attempt to restore the exact pre-Benzo values recorded per profile
- **Conflict recovery** — Keep Current, Restore Recorded Original Anyway, or Defer retains explicit recovery choices
- **Sleep Now unavailable** — sleep commands and timed sleep remain disabled
- **Diagnostics** — Option-click the menubar icon for existing sleep sessions, wake reasons, USB devices and settings observations; these do not prove recovery or hardware behavior

### Recovery and removal

Legacy recovery is administrator-assisted: historical flat originals do not
establish profile identity, and the app will not infer or adopt those values.
Review the prior controller and exact affected settings with an administrator;
preserve the original evidence and existing rule. Rule retirement is a separate
administrator action after recovery and verification. Removing the app is not
verified restoration or permission-rule retirement. The cask preserves the
backup and existing rule during removal. Do not delete invalid or unreadable
evidence to reactivate the app. Seek help through
[GitHub issues](https://github.com/chrisrogers37/benzo/issues).

## Requirements

- macOS Ventura (13.0) or later
- Intel or Apple Silicon
- macOS administrator authorization for settings writes; prompt caching is
  managed by macOS, and no new passwordless sudoers rule is installed

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
command and login adapters. Tests use injected commands, clocks and temporary
storage. The bounded read runner's fixture exception does not exercise privileged
execution. Full-Xcode Debug/Release builds and unhosted XCTest are required; a
Command Line Tools-only Swift check is not an XCTest pass. Native acceptance and
release remain incomplete. For this task, acceptance on this Mac Mini is limited
to launching the task build, temporary selected-setting apply/restore with
administrator prompts, relaunch and quit. It excludes sleep/reboot, permission
rule or login-item changes, installation/removal and terminating other fleet
processes. These checks do not establish physical sleep or USB behavior.

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
The recovery transport uses fixed per-profile reads and foreground exact-cell
administrator-authorized writes. Request completion and subsequent readback are
separate evidence; neither establishes physical sleep behavior.

The `build` workflow runs web tests/build, full-Xcode Debug and core tests, and
uploads a seven-day universal `.xcarchive` with distribution signing disabled as CI build evidence. It is
not distribution signing, a release candidate, or a release platform. The
separate `security` workflow retains npm audit and Gitleaks. The connected Vercel
Git integration can deploy previews on branch pushes and the site on main;
inspect and authorize deployment before push.

The accepted delivery order is 03 → 01 → 04 → conditional 02 in the
[remediation plan](documentation/planning/tech_debt/benzo-remediation_2026-11-02/00_TECH_DEBT.md).
Older reorientation plans and their run log remain historical safety references.

## License

MIT
