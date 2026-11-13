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

**Power Access** provides one explicit administrator-approved setup for the Mac
account using Benzo. It installs a finite, one-shot power command and a rule for
that account; no daemon or background service is installed. Ordinary On, Off and
quit use the retained grant without another administrator prompt. Programs running
as that account can invoke the same limited commands; this is account-level
access, not an app-exclusive privilege. The separate legacy-rule observation never
installs, repairs or retires the old `/private/etc/sudoers.d/benzo` rule.

## Install

**Download** the latest `.dmg` from [Releases](https://github.com/chrisrogers37/benzo/releases).

The existing v0.3.0 download predates the current power-access, recovery and
interface changes. The account-free build below is functional source output and
has not yet completed native acceptance or publication. No Apple Developer
membership is needed to build it or use its power controls after setup.

An ad-hoc build is unnotarized. After a trusted browser download, copy the app to
Applications. If macOS blocks opening it and you choose to trust that exact copy,
use **System Settings → Privacy & Security → Open Anyway**, then confirm Open.
This is a per-app decision; keep Gatekeeper enabled and preserve quarantine.
See [Apple’s opening guidance](https://support.apple.com/en-us/102445). Signing
and notarization are optional distribution improvements, separate from power setup.

**Homebrew** (personal tap):
```
brew tap chrisrogers37/benzo
brew install --cask benzo
```

## What it does

Benzo lives in your menubar. It captures the available AC, battery and UPS
profiles, then applies only selected settings and profile/key values that are
reported and supported. **Set Up Power Access** asks once for administrator
approval and names the local account receiving access. The selected power settings
affect everyone using this Mac. Normal apply, restore, quit and relaunch reuse the
grant. **Repair / Update Power Access** is an explicit administrative action when
the installed tool needs attention; ordinary app updates keep working with a
compatible installed tool. Readback checks reported values; hardware sleep
behavior is a separate outcome. The latest public release remains v0.3.0.

A setting is unavailable when any required key is absent from a reported
profile. Benzo disables that control and reports the missing profile/key; it
does not invent profiles or values.

See the [privacy notes](PRIVACY.md) for
what Benzo stores on your Mac and what the website does.

### Features

- **Manual settings** — choose available settings before applying; selections freeze for the session
- **Captured originals** — Off, System Defaults and quit attempt to restore the exact pre-Benzo values recorded per profile
- **Conflict recovery** — Keep Current, Restore Recorded Original Anyway, or Defer retains explicit recovery choices
- **Sleep Now unavailable** — sleep commands and timed sleep remain disabled
- **Diagnostics** — Option-click the menubar icon for existing sleep sessions, wake reasons, USB devices and settings observations; these do not prove recovery or hardware behavior
- **Account-specific setup** — the command checks the setup account's UID and persistent local account identity; another account cannot inherit access by reusing a user ID
- **Manual update check** — Check for Updates contacts GitHub only when requested;
  View Release opens the verified release page. There is no automatic downloader
  or installer, and results clear when the popover closes.

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

Legacy backup bytes, an unretired rule, or saved legacy-active state without a
final journal keep normal controls unavailable. This version has no in-app legacy acknowledgement or
migration; administrator review alone does not clear those gates. Preserve the
evidence while arranging recovery and retirement outside the app.

Recovery storage requires an account-owned private directory (0700) and regular
private files (0600). Older installations may have different permissions. An
interrupted save may also leave `.benzo-*.tmp` evidence in
`~/Library/Application Support/Benzo`. For either storage error, preserve the
entire directory and ask an administrator to inspect its ownership, permissions,
and recovery generations together with execution evidence. Do not automatically
change permissions or remove temporary files to bypass Recovery Required.

The one-shot command is installed at
`/Library/PrivilegedHelperTools/com.chrisrogers37.benzo-command`; its exact policy is
`/private/etc/sudoers.d/benzo-command`. The policy grants only fixed commands with
the installed binary’s digest to the setup account, not arbitrary shell commands
or unrestricted `pmset`. The command rechecks the account’s UID and persistent
GeneratedUID and accepts bounded, typed requests. Root-owned account and execution
evidence stays in `/private/var/db/com.benzo.command` (0700, files 0600). Missing,
corrupt or interrupted evidence fails closed; no administrator credentials are stored.

Open the app from Applications, then complete setup. Before repair, removal or app
replacement, restore or resolve the settings session. **Power Access → Remove
Power Access** requires confirmation and resolved Off. It removes only the exact
recognized rule and installed command, retaining account ownership and recovery
records. Removal is not restoration or account transfer. Reinstallation requires
explicit setup and retains the original owner. If revocation or a missing tool
prevents restoration, preserve the app and records for administrator-assisted
recovery; do not delete evidence to bypass the gate.

Historical daemon builds may leave a service and `/private/var/db/com.benzo.helper`
state. Restore with the old build and resolve those artifacts explicitly before
switching to the command architecture. The new app does not adopt or erase old
daemon authority, legacy flat backups, or old sudoers rules automatically.
The remaining installation and native checks are in the
[account-free acceptance checklist](docs/account-free-acceptance.md).

## Requirements

- macOS Ventura (13.0) or later
- Intel or Apple Silicon
- One administrator approval for initial power-access setup, limited to the account using Benzo
- No Apple Developer account, Developer ID signature, notarization or background-service approval is required for the power controls
- App opening remains subject to macOS security policy; the account-free artifact is explicitly unnotarized

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
release remain incomplete. Use the [native acceptance checklist](docs/account-free-acceptance.md)
on an approved test Mac after the code and artifact checks are complete. Never
run privileged acceptance, sleep/reboot or unrelated fleet operations on the
always-on host without the owner’s explicit authorization. These checks do not
establish physical sleep or USB behavior.

## Package a functional account-free build

The compatibility flag remains `--mode development`. It produces a functional
account-free build with no Apple Developer membership or signing credentials:

```sh
./scripts/build-dmg.sh --mode development --output-dir /absolute/new/benzo-development
```

Full Xcode is required. The output directory must be new and its parent must
already exist. The resulting development DMG contains `Benzo Development.app`
and an Applications shortcut, with checksums and source provenance alongside it.
It is ad-hoc signed and unnotarized, with power controls available after explicit
setup. Its filename differs from the public app, but it shares Benzo’s bundle
identifier and recovery storage; do not run two copies together. CI builds and
inspects the real DMG without installing, launching or granting power access.

The [release preparation guide](docs/release-preparation.md) covers artifact
checks and optional Developer ID signing/notarization. The
[native acceptance checklist](docs/account-free-acceptance.md) collects the
remaining user-involved checks. No packaging command publishes a release.

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
The recovery transport uses unprivileged per-profile reads and the installed
one-shot command through noninteractive `sudo` for exact-cell writes. The command
invokes fixed `/usr/bin/pmset` argument arrays, serializes admission, checks expected
values and durable revisions, and preserves uncertain execution across invocations.
AppleScript requests administrator approval only for explicit setup, repair/update
or removal; ordinary controls never fall back to an authorization prompt.
Request completion and subsequent readback are separate evidence; neither
establishes physical sleep behavior.

The `build` workflow runs web tests/build, full-Xcode Debug/Release builds and core tests, and
uploads a seven-day universal `.xcarchive` with distribution signing disabled plus
a functional account-free DMG with packaging evidence. These are
not Developer ID signing, notarization or native permission acceptance. The
separate `security` workflow retains npm audit and Gitleaks. The connected Vercel
Git integration can deploy previews on branch pushes and the site on main;
inspect and authorize deployment before push.

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
