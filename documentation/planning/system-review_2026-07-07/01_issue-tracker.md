# Benzo Issue Tracker — Full System Review 2026-07-07

Each item is written so it can be copied 1:1 into a GitHub issue (title = heading,
body = the rest). Suggested labels are given per item. **Size** describes invasiveness,
not calendar time: S = localized edit, M = touches several files or needs a small
refactor, L = structural change or new subsystem.

Priorities:

- **P0** — breaks the core safety promise ("we always restore your settings") or blocks
  paid distribution. Fix before any marketing push or paywall.
- **P1** — high-impact bugs, security gaps, release blockers.
- **P2** — medium bugs, tech debt, UX/SEO/accessibility gaps.
- **P3** — polish, dead code, documentation drift.

---

## P0 — Safety promise & distribution blockers

### BZ-001 · Settings are only restored on the footer Quit button — no termination hook
`bug` `safety` — Size: M — `Benzo/App/AppDelegate.swift`, `Benzo/ViewModels/BenzoViewModel.swift:117-122`

The "quit restores defaults" guarantee only runs when the user clicks Quit inside the
popover. There is no `applicationShouldTerminate`/`applicationWillTerminate` in
`AppDelegate` (the only `terminate` call in the codebase is inside `quit()`), so Cmd+Q,
logout, restart, Force Quit, `kill`, or a crash all leave `hibernatemode 25` and the
other five settings applied system-wide. `isActive` persists in UserDefaults, so after
reboot the UI shows "on" whether or not pmset still matches.

**Fix:** implement `applicationShouldTerminate` to run the same restore path (delaying
termination with `.terminateLater` until restore completes), listen for
`NSWorkspace.willPowerOffNotification`, and add launch-time reconciliation (see BZ-009).
Crash-safety ultimately needs the backup-file approach to be authoritative: on next
launch, if a backup exists and `isActive` is false, offer to restore.

### BZ-002 · `PMSetState` parser is fragile and can write a corrupt backup that breaks restore
`bug` `safety` — Size: M — `Benzo/Models/PMSetState.swift:7-18`, `Benzo/Services/BackupService.swift:15-18`

Parsing splits each line on the first **space** only. `pmset -g` output contains tabs,
multi-word keys ("Sleep On Power Button"), section headers ("Currently in use:"), and
annotated values ("1 (sleep prevented by ...)"). Garbage entries land in the backup
JSON; `isValidPMSetParam` then rejects them at restore time, so deactivate/quit/revert
can fail or partially apply — the failure mode is discovered exactly when the user
needs restore to work.

**Fix:** parse `pmset -g custom` or extract only the "Currently in use" section, split
on all whitespace, strip parenthetical annotations, and validate the backup at **save**
time (fail activation loudly rather than persist garbage). Add fixture-based unit tests
with real `pmset` output from Intel and Apple Silicon Macs (depends on BZ-020).

### BZ-003 · Deactivate with a missing/corrupt backup silently pretends success
`bug` `safety` — Size: S — `Benzo/ViewModels/BenzoViewModel.swift:272-278`

If `BackupService.load()` fails, `deactivate()` sets `isActive = false` and returns —
UI says Deep Sleep is off while pmset may still be in hibernatemode 25. Same product
lie as BZ-001 but reachable in normal use.

**Fix:** treat missing/corrupt backup as an error state: keep the toggle on, show an
actionable message, and offer an explicit "restore macOS defaults" fallback (known-good
default values per key) that requires user confirmation.

### BZ-004 · `quit()` swallows restore failures with `try?`
`bug` `safety` — Size: S — `Benzo/ViewModels/BenzoViewModel.swift:117-122`

Both the backup load and the restore in `quit()` use `try?`. Any failure is invisible
and the app terminates leaving modified settings. This is the single most important
error path in the product.

**Fix:** on failure, present a blocking alert ("Couldn't restore your sleep settings —
Retry / Quit Anyway") and only terminate after success or explicit override. Log the
failure (BZ-035).

### BZ-005 · Partial pmset apply with no rollback
`bug` `safety` — Size: M — `Benzo/Services/PMSetService.swift:24-51`

`applySettings` applies keys sequentially; a mid-loop failure leaves a mixed system
state (some keys Benzo's values, some original) with no rollback attempt and UI state
that doesn't reflect reality.

**Fix:** snapshot state before applying; on failure, restore already-applied keys from
the snapshot and surface a clear error. Report partial-failure distinctly.

### BZ-006 · Notarization pipeline in `build-dmg.sh` is broken
`release-blocker` `build` — Size: M — `scripts/build-dmg.sh`

Several defects combine to make the credentialed path unusable:
1. When Developer ID export fails, the script falls back to the **ad-hoc-signed** app
   (lines 53-58) but still submits it to notarization if credentials are set — Apple
   rejects ad-hoc signatures, and under `set -euo pipefail` the script dies before the
   DMG is created.
2. `ExportOptions.plist` (lines 35-46) lacks `teamID`/`signingCertificate`, so export
   fails on machines with multiple teams.
3. `VERSION` (line 10) is unvalidated — an empty value produces `Benzo-.dmg`.
4. `notarytool submit` on a bare `.app` (should `ditto -c -k` zip first); no JSON
   status parsing or log capture on `Invalid`.
5. No `codesign --verify --deep --strict` gate; header claims "sign" but no explicit
   signing/verification step exists.

**Fix:** branch explicitly — notarize only when `codesign -dv` confirms a Developer ID
signature; otherwise skip with a warning and still build the (community) DMG. Add
teamID to export options, fail fast on empty VERSION, zip before submit, verify
signature, write `build/SHA256SUMS`.

### BZ-007 · No hardened runtime or entitlements configured
`release-blocker` `build` — Size: S — `Benzo/Benzo.xcodeproj/project.pbxproj`

Only `CODE_SIGN_STYLE = Automatic` is set; there is no `.entitlements` file, no
`CODE_SIGN_ENTITLEMENTS`, and no `ENABLE_HARDENED_RUNTIME = YES`. Notarization requires
hardened runtime. This must land before BZ-006 can succeed end-to-end.

**Fix:** add a minimal entitlements plist, enable hardened runtime for Release, verify
the app still functions (Process/osascript spawning is fine under hardened runtime
without extra entitlements, but confirm).

### BZ-008 · No LICENSE file; license strategy undecided for monetization
`release-blocker` `legal` — Size: S — repository root, `README.md:66-68`

README claims MIT but there is no `LICENSE` file. This is both a legal ambiguity for
the current open-source distribution and a **strategic decision gate** for revenue: if
the code stays MIT, anyone can redistribute builds for free, which constrains the
monetization model to donations/pay-what-you-want/paid-convenience (signed builds +
auto-updates) rather than a license-enforced paywall.

**Fix:** decide the model first (see roadmap §3), then either commit the MIT LICENSE
(open-core / donationware path) or relicense before taking any outside contributions
(currently sole-author, so relicensing is still trivially possible).

---

## P1 — High-impact bugs, security, release blockers

### BZ-009 · `isActive` is never reconciled with real pmset state at launch
`bug` — Size: M — `Benzo/ViewModels/BenzoViewModel.swift:36-67, 192-226`

`isActive` comes from UserDefaults; drift correction only runs on popover open, not at
login-item startup. After a reboot, macOS update, or manual `pmset` change, the icon
and the system disagree. **Fix:** on launch (and on wake notifications), read pmset,
compare against expected state, and reconcile or surface a warning.

### BZ-010 · `toggleSetting` doesn't revert the checkbox when apply fails
`bug` — Size: S — `Benzo/ViewModels/BenzoViewModel.swift:93-98, 291-303`

State mutates before the shell call; on failure an error shows but the checkbox stays
flipped. The `// Revert toggle` comment at line 299 has no code under it. **Fix:**
revert `settingStates[setting]` in both catch branches (or apply-then-commit).

### BZ-011 · All shell execution blocks the calling (main) thread
`bug` `performance` — Size: M — `Benzo/Services/ShellExecutor.swift:90-115`, all call sites in `BenzoViewModel`

`Process.waitUntilExit()` runs synchronously; activate/deactivate/toggle/setup all run
on the main thread, freezing the popover for the duration of sudo+pmset (worse: the
osascript path blocks the UI for as long as the password dialog is open). **Fix:** move
shell I/O to a background queue or actor, publish results on the main actor, and
disable controls while an operation is in flight.

### BZ-012 · Silent sudoers reinstall at launch triggers an unexplained admin prompt
`security` `ux` — Size: S — `Benzo/ViewModels/BenzoViewModel.swift:62-66`

If `needsSudoersUpdate`, init fires `try? ShellExecutor.installSudoersRule()` — an
osascript **admin password dialog** with no user action and swallowed errors. Users
should never see a privilege prompt they didn't initiate; this trains bad security
habits and looks like malware. **Fix:** show an in-popover banner ("Benzo needs to
update its permission rule") that triggers the prompt on click.

### BZ-013 · Master toggle can be "On" while applying nothing
`bug` `ux` — Size: S — `Benzo/ViewModels/BenzoViewModel.swift:252-263`

With all checkboxes off, activation applies an empty list but still sets
`isActive = true` — UI says "Sedated" while nothing changed; drift correction also
no-ops (`guard !enabled.isEmpty`). **Fix:** require at least one enabled setting to
activate (disable the toggle with a hint), or auto-enable Deep Sleep (hibernatemode).

### BZ-014 · Backup is only captured once, so re-activation can restore stale values
`bug` — Size: S — `Benzo/ViewModels/BenzoViewModel.swift:254-258`, `Benzo/Services/BackupService.swift`

Backup is written only when `!hasBackup()`. Deactivate → change pmset manually →
re-activate: deactivating later restores the outdated snapshot. **Fix:** refresh the
backup on every activation from the *inactive* state (at that moment current pmset
values are by definition the user's own).

### BZ-015 · Non-admin users pass "setup" but every pmset call fails
`bug` `ux` — Size: S — `Benzo/Services/ShellExecutor.swift:82-84`

The sudoers rule grants NOPASSWD to `%admin` only. A standard user's setup appears to
complete (file exists ⇒ `isSetupComplete`), but `sudo -n` always fails with a cryptic
error. **Fix:** check group membership during setup and block with a clear "Benzo
requires an administrator account" message.

### BZ-016 · Scheduled sleep timer survives deactivate/quit and re-activates the app
`bug` — Size: S — `Benzo/ViewModels/BenzoViewModel.swift:160-188, 272-289`

`cancelScheduledSleep()` is not called from `deactivate()`/`quit()`. A user who sets a
30-minute timer and then turns Benzo off still gets their caffeinate processes killed
and the Mac force-slept (via `sleepNow()`, which re-activates Benzo). **Fix:** cancel
the timer in deactivate and quit; also cancel the 0.5s `sleepNow` closure (BZ-023).

### BZ-017 · README's Homebrew tap instructions point to a repo that doesn't exist
`release-blocker` `docs` — Size: S — `README.md:15-19`, `Casks/benzo.rb`

`brew tap chrisrogers37/benzo` → `chrisrogers37/homebrew-benzo` returns 404. The v0.3.0
release notes correctly use the direct raw-cask URL instead. **Fix:** create the
`homebrew-benzo` tap repo (cask contents already correct), or rewrite the README to the
direct-cask install command until the tap exists.

### BZ-018 · No release automation (tag → DMG → GitHub release → cask bump)
`ci` `release-blocker` — Size: M — `.github/workflows/`

Releases are fully manual: run `build-dmg.sh` locally, upload by hand, edit the cask
sha256 by hand. Every manual step is a chance for the DMG/cask/README to drift (the
package.json already says 0.1.0). **Fix:** `release.yml` on tag push using a `macos-*`
runner: build via `build-dmg.sh` (after BZ-006), attach DMG + SHA256SUMS, patch
`Casks/benzo.rb`, populate release notes from CHANGELOG. Store signing/notarization
secrets in GitHub Actions secrets.

### BZ-019 · CI never compiles anything — broken Swift or JSX can merge to main
`ci` — Size: S — `.github/workflows/security.yml`

The only workflow runs `npm audit` + gitleaks. **Fix:** add a landing-page job
(`npm ci && npm run build`, ubuntu runner) and a macOS job
(`xcodebuild -project Benzo/Benzo.xcodeproj -scheme Benzo -configuration Debug build`)
required on PRs.

### BZ-020 · Zero tests; parsing and sudoers generation are untested
`tech-debt` `testing` — Size: M — project-wide

No test target exists. The highest-risk logic — `PMSetState` parsing, backup round-trip,
`buildSudoersRule()`, wake-reason mapping, sleep-log pairing — is exactly the kind of
pure-ish logic that unit tests cover well. **Fix:** add a macOS unit-test target to the
Xcode project, fixture tests for the parsers using captured real `pmset` output, run in
the CI job from BZ-019. Requires the DI refactor in BZ-037 for service-level tests, but
parser tests need no refactor and should land first.

### BZ-021 · Social preview image 404s in production
`bug` `marketing` — Size: S — `index.html:13,19`, `public/`

`og:image`/`twitter:image` reference `/og-image.png`, which doesn't exist —
every social share of the landing page shows a broken preview. **Fix:** add a
1200×630 `public/og-image.png` and use absolute URLs.

### BZ-022 · `pmset -a` silently changes sleep behavior for every user on the Mac
`bug` `docs` — Size: S — `Benzo/Services/PMSetService.swift`

All writes are system-wide (`-a`); on shared Macs, one account activating Benzo alters
hibernation for all accounts, and nothing in the UI or docs says so. **Fix:** at
minimum, document prominently (README + first-run setup screen). Optionally detect
multiple local users and note it in the setup flow.

---

## P2 — Medium bugs, tech debt, UX/SEO/accessibility

### BZ-023 · `sleepNow`'s 0.5s delayed closure can fire after quit/deactivate
`bug` — Size: S — `Benzo/ViewModels/BenzoViewModel.swift:141-149`

The `asyncAfter` closure holding `pmset sleepnow` isn't cancellable; a user can
deactivate or quit within the window and still get slept. **Fix:** use a cancellable
work item, cancel in deactivate/quit.

### BZ-024 · Settings verification shows green when it has nothing to verify
`bug` `diagnostics` — Size: S — `Benzo/Services/DiagnosticService.swift:132-150`

When inactive, expected == actual so every row passes; when active with a setting
disabled, `matches` is true even if pmset still holds Benzo's value. "All settings
verified" can be false comfort. **Fix:** show "inactive — N/A" when off; compare
disabled settings against backup values when on.

### BZ-025 · Disabling a setting whose keys are missing from backup silently keeps Benzo's values
`bug` — Size: S — `Benzo/Services/PMSetService.swift:40-50`

`applySettingsWithRestore` skips keys absent from the backup with no warning. **Fix:**
warn/log on missing keys; fall back to documented safe defaults or fail loudly.

### BZ-026 · Timed sleep kills every caffeinate process the user runs
`bug` — Size: M — `Benzo/Services/PMSetService.swift:80-84`

`pkill caffeinate` is indiscriminate — it kills a caffeinate the user started for a
download or presentation, not just sleep blockers. **Fix:** parse
`pmset -g assertions` for blocking PIDs and kill selectively; show what will be killed
in the timer UI.

### BZ-027 · Launch-at-login toggle stays on when registration fails
`bug` `ux` — Size: S — `Benzo/ViewModels/BenzoViewModel.swift:313-325`

On `SMAppService.register()` failure, the binding stays true while the system status is
`.notRegistered`. **Fix:** re-read `SMAppService.mainApp.status` in the catch and set
the published property from it.

### BZ-028 · Global click monitor: nil return unchecked, monitor leaks
`bug` — Size: S — `Benzo/App/AppDelegate.swift:113-115` (+ unused `NSPopoverDelegate` conformance, line 4)

`addGlobalMonitorForEvents` can return nil; the monitor is only removed in
`closePopover`, and `NSPopoverDelegate` is adopted with zero methods implemented.
**Fix:** implement `popoverDidClose` to remove the monitor; handle nil.

### BZ-029 · Sleep-log parsing relies on locale/version-sensitive substrings
`bug` `diagnostics` — Size: M — `Benzo/Services/DiagnosticService.swift:22-74, 155-169`

`pmset -g log` heuristics (`Entering Sleep state`, tab-delimited fields, space-split
dates) vary across macOS versions; parsing can silently yield empty or mispaired
sessions. **Fix:** capture logs from each supported macOS version as fixtures, test
against them (BZ-020), and degrade gracefully with a "couldn't parse sleep log" state.

### BZ-030 · Wake reason `contains("User")` mislabels UserActivity wakes as "Power Button"
`bug` `diagnostics` — Size: S — `Benzo/Models/SleepSession.swift:38`

**Fix:** match specific tokens (`PowerButton`, `EC.User`) before the generic fallback.

### BZ-031 · Apple Silicon vs Intel hibernation differences are unhandled
`enhancement` — Size: M — `Benzo/Models/SleepSetting.swift:44-45`

`hibernatemode 25` semantics and the standby/autopoweroff interplay differ across
platforms and macOS versions; the app applies one fixed set unconditionally. **Fix:**
detect platform, adjust/document per-platform behavior, warn on unsupported configs.
This matters for support burden once paying users arrive.

### BZ-032 · Diagnostics USB panel is empty on modern Macs
`bug` `diagnostics` — Size: S — `Benzo/Services/DiagnosticService.swift:78-91`

Only `SPUSBDataType` is queried; Apple Silicon exposes many devices elsewhere. **Fix:**
merge additional `system_profiler` data types or relabel the panel honestly.

### BZ-033 · Backup file is world-default-permission JSON with no integrity check
`security` — Size: S — `Benzo/Services/BackupService.swift:15-24`

Restore validation prevents injection (good), but any local process can rewrite the
backup to push pmset to arbitrary numeric values on next restore. **Fix:** chmod 0600,
validate values against per-key known-good ranges on load.

### BZ-034 · No uninstall story; sudoers rule lives forever
`enhancement` `security` — Size: M — `Benzo/Services/ShellExecutor.swift:69-73`, `Casks/benzo.rb:14-15`

`removeSudoersRule()` exists but is never called; the cask's
`uninstall delete: "/etc/sudoers.d/benzo"` can't remove a root-owned file. **Fix:** add
an "Uninstall Benzo…" action (restore settings → remove sudoers via admin prompt →
offer to trash app), replace the cask stanza with a `caveats` block documenting manual
cleanup.

### BZ-035 · No structured logging or crash reporting
`enhancement` — Size: M — project-wide

Restore failures, sudo errors, and parse failures are invisible for support. **Fix:**
adopt `os.Logger` with subsystems (shell, backup, restore, diagnostics); consider
opt-in crash reporting (e.g. Sentry) before charging money — support burden without
logs will be brutal.

### BZ-036 · No auto-update mechanism
`enhancement` `revenue` — Size: L — project-wide

No Sparkle/appcast; users must check GitHub releases manually, and stale installs keep
old sudoers rules. Auto-update is also the delivery vehicle for a paid tier ("keep
getting updates"). **Fix:** integrate Sparkle 2, generate the appcast in the release
workflow (BZ-018), serve it from the landing page domain.

### BZ-037 · `BenzoViewModel` is a god object; static service enums block testing
`tech-debt` — Size: L — `Benzo/ViewModels/BenzoViewModel.swift` (326 lines), all Services

One class owns activation, backup, setup, diagnostics, sleep timer, drift correction,
login item, and quit; services are static enums with hard-coded paths, so nothing can
be mocked. **Fix:** extract protocols (`PMSetExecuting`, `BackupStoring`), inject them,
and split the view model (activation controller / diagnostics / scheduler). Do this
incrementally alongside the P0 safety fixes rather than as a big-bang rewrite.

### BZ-038 · Landing page is a 1,370-line monolith
`tech-debt` `web` — Size: L — `src/BenzoHybrid.jsx`

Mockup, marketing sections, diagnostics demo, and Gatekeeper tray live in one file with
inline styles. Every native UI change (which the project rules require mirroring)
means editing this file blind. **Fix:** split into `Mockup/`, `Marketing/`,
`GatekeeperTray`, a shared `theme.js`, and a constants module mirroring
`SleepSetting.swift` labels.

### BZ-039 · Landing page has no keyboard/AT accessibility
`accessibility` `web` — Size: M — `src/BenzoHybrid.jsx` (throughout)

Interactive mockup controls are `div onClick` — no `aria-*`, no `tabIndex`, no
buttons; a `<button>` is nested inside an `<a>` in the CTA (invalid HTML); animations
ignore `prefers-reduced-motion`. **Fix:** real `<button>`s with `aria-pressed`/
`aria-expanded`, unnest the CTA, add a reduced-motion media query.

### BZ-040 · SEO gaps: no canonical/og:url, robots.txt, sitemap, or structured data
`seo` `web` — Size: S — `index.html`, `public/`

**Fix:** canonical link + `og:url`, `robots.txt`, `sitemap.xml`, and JSON-LD
`SoftwareApplication` with `downloadUrl`, `operatingSystem`, `softwareVersion`.

### BZ-041 · Landing page claims "macOS Catalina and later"; app requires Ventura 13+
`bug` `web` — Size: S — `src/BenzoHybrid.jsx:1193-1195` vs `README.md:47`, `Casks/benzo.rb:10`

Users on Catalina–Monterey will download a broken app. **Fix:** change the copy to
"macOS Ventura (13.0) or later".

### BZ-042 · Security-audit Phase 02 never completed (.env hygiene, Vite major upgrade)
`security` `tech-debt` — Size: S — `.gitignore`, `package.json`, `documentation/planning/security/full-audit_2026-03-21/02_env-hygiene-and-deps.md`

`.gitignore` still lacks `.env*` entries (notarization creds risk); Vite remains on 6.x
with the planned major upgrade undone. **Fix:** complete Phase 02 as written; mark the
doc's checklist.

---

## P3 — Polish, dead code, doc drift

### BZ-043 · Mockup drift from native app (5 known gaps)
`web` `mockup-sync` — Size: M — `src/BenzoHybrid.jsx`

Per the project's own sync rule: (a) missing "Launch at Login" footer toggle,
(b) no SetupView/first-run permission screen in the mockup, (c) blocker shows raw
`caffeinate` instead of a friendly name, (d) `showOptions` defaults open vs closed in
the app, (e) marketing pmset list omits `womp 0` (7th setting). Fix as one sync pass.

### BZ-044 · Hardcoded `v0.3.0` in `FooterView` will drift from MARKETING_VERSION
`tech-debt` — Size: S — `Benzo/Views/FooterView.swift:26`

Read `CFBundleShortVersionString` from the bundle instead.

### BZ-045 · Force unwraps and IUOs in AppDelegate/BackupService
`tech-debt` — Size: S — `Benzo/App/AppDelegate.swift:5-6,47`, `Benzo/Services/BackupService.swift:5`

Replace with guard/optional binding.

### BZ-046 · Dead code and unused parameters
`tech-debt` — Size: S — `DiagnosticService.extractAssertionName` (never called), `MasterToggleView.activeCount`, `SettingRowView.isActive`, `OriginalSettingsBackup.capturedAt`

Remove or actually use them.

### BZ-047 · Misleading `ShellError.userCancelled` catches on paths that never prompt
`tech-debt` — Size: S — `BenzoViewModel.swift:110,150,265,284,298`

`runDirectWithSudo` uses `sudo -n` and never prompts; the empty userCancelled catches
on activate/deactivate/toggle silently swallow nothing-that-can-happen and confuse
readers. Remove them.

### BZ-048 · Empty SwiftUI Settings scene
`ux` — Size: S — `Benzo/App/BenzoApp.swift:7-10`

Opening app preferences shows a blank window. Remove the scene or populate it
(about, uninstall, permission status).

### BZ-049 · Menubar icon color duplicates BenzoTheme accent inline
`tech-debt` — Size: S — `Benzo/App/AppDelegate.swift`

Share one constant (NSColor bridge in `BenzoTheme`).

### BZ-050 · Diagnostics errors collapse to empty arrays with no user-visible cause
`ux` `diagnostics` — Size: S — `Benzo/Services/DiagnosticService.swift`, `Benzo/Views/DiagnosticView.swift:180-181`

Propagate errors to a published `diagnosticsError` and render it.

### BZ-051 · Info.plist/build-number hygiene
`tech-debt` — Size: S — `Benzo/Info.plist`, `project.pbxproj`

`LSUIElement` set in both plist and generated keys; `CURRENT_PROJECT_VERSION` frozen
at 1. Consolidate; bump build numbers in the release workflow.

### BZ-052 · Version drift across package.json (0.1.0) vs app/cask/docs (0.3.0)
`tech-debt` — Size: S — `package.json:4`

Align or pin the landing package at a neutral version with a comment; add version bump
to the release checklist.

### BZ-053 · No `vercel.json`; deploy config lives only in the Vercel dashboard
`tech-debt` `web` — Size: S — repository root

Add `vercel.json` (SPA config) so the deployment is reproducible from the repo.

### BZ-054 · Landing page: direct download link, self-hosted fonts, notarization copy
`web` `enhancement` — Size: S — `src/BenzoHybrid.jsx`, `index.html:22-24`

(a) CTA links to the releases index, not the DMG asset — deep-link the latest asset
once release automation (BZ-018) guarantees a stable name. (b) Google Fonts CDN is a
third-party request; self-host in `public/fonts/`. (c) The "isn't notarized yet"
Gatekeeper tray copy (also README) must be updated/removed the moment BZ-006/BZ-007
ship, or it will undercut the paid positioning.

---

## Cross-cutting dependency notes

- **BZ-007 → BZ-006 → BZ-018 → BZ-036/BZ-054(a)**: entitlements before notarization
  before release automation before auto-update/deep links.
- **BZ-020 (test target) should land immediately after BZ-002** so the new parser ships
  with fixtures; **BZ-037 (DI refactor)** unlocks the rest of the test surface.
- **BZ-001/003/004/005/009/014/016** all touch the activate/restore lifecycle — fix as
  one coherent "settings lifecycle" workstream to avoid churn, then reflect any UI
  changes in the mockup (BZ-043).
