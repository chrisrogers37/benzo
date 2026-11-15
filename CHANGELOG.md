# Changelog

All notable changes to Benzo are documented here.

## [Unreleased]

### Added
- **Sleep Now and timer (0.5.0 development)** — request sleep after applying settings, immediately or after 5, 15, 30 or 60 minutes. Cancel a countdown by clicking it; Off, quit, recovery and system sleep/wake cancel it. No timer survives app restart.
- Explicit power-access update for the additional account-level sleep command. Existing 0.4.0 power access continues to support apply and restore.
- Durable sleep-request evidence and no-replay recovery, separate from captured settings. A reported request result does not establish physical sleep.
- **Full system review (2026-07-07)** — Triaged 54 issues (BZ-001–BZ-054) covering the
  settings-restore lifecycle, notarization pipeline, CI gaps, and landing-page fixes
  into `documentation/planning/system-review_2026-07-07/`, with a milestone roadmap to
  a signed, notarized, revenue-generating release.

## [0.4.0] - 2026-11-15

### Added
- Account-free power access: one administrator setup for the local Mac account, followed by apply, restore, quit and relaunch without repeated approval.
- Durable per-profile recovery records, verified restores, conflict choices and recovery after interrupted operations.
- Manual Check for Updates, keyboard-accessible controls, improved text contrast and bounded scrolling.
- Native XCTest, web interaction tests and universal macOS DMG builds in CI.

### Changed
- The main panel uses a slim Manage Power Access pill below Sleep Now. Routine status caveats are removed; errors and recovery instructions remain visible when needed.
- Restore Settings replaces the misleading System Defaults label. It restores captured pre-Benzo values.
- Repair and removal controls appear under Advanced in the ready power-access screen.
- The downloadable account-free build is ad-hoc signed and unnotarized; macOS may require its per-app Open Anyway approval. No Apple Developer account is needed.

### Removed
- Automatic setting reapplication, sleep-blocker termination and launch-time permission changes.
- Sleep Now and its timer remain unavailable in this release. The Sleep Now button stays disabled; restoring sleep and timer functionality is separate follow-up work.

### Validation
- The account-free flow was observed on source `09ce88f` (0.3.0 build 1), on an Apple silicon Mac Mini with macOS 26.1: one setup approval, Disable Network Wake apply/restore, apply/quit and relaunch. Both restores matched the full recorded power-settings baseline; no further approval was reported for Off, the second On/Quit cycle or relaunch.
- That evidence predates the final v0.4.0 UI/package. Other-account isolation, native failure paths, removal/reinstall, upgrade and native VoiceOver checks remain untested; see [the acceptance record](docs/account-free-acceptance.md).
- Physical sleep and timer behavior are outside this release's validation.

## [0.3.0] - 2026-06-01

### Added
- **Timed sleep** — Tap the clock icon on the Sleep Now button to reveal a timer picker (5m / 15m / 30m / 60m). When the timer fires, all caffeinate processes are killed before triggering `pmset sleepnow`, so the Mac actually enters hibernation. Tap the countdown to cancel.
- **Sleep blocker awareness** — On popover open, Benzo lists any apps currently asserting `PreventUserIdleSystemSleep` (e.g. caffeinate, video calls) with friendly display names so you can see what's keeping the Mac awake.
- **Split-button Sleep Now** — Visible clock icon next to "Sleep Now" replaces the previous hidden ⌘+click gesture for accessing the timer.

### Changed
- **Sudoers rule** — Narrowed `/etc/sudoers.d/benzo` from `pmset *` to a specific allowlist of `sleepnow` and `pmset -a <key> [0-9]*` for keys derived from `SleepSetting.allCases`. Validated with `visudo -cf` before install; versioned via `sudoersRuleVersion` in UserDefaults for migration.

### Security
- **Direct argv exec for pmset** — `ShellExecutor` now spawns `pmset` directly with argv instead of `/bin/sh -c`, eliminating shell-interpretation attack surface.
- **Backup value validation** — `PMSetService` validates pmset backup values before shell interpolation.
- **Dependency CVE patches** — Bumped `vite`, `picomatch`, and `postcss` to patched versions.
- **CI security checks** — Added `npm audit --audit-level=moderate` and gitleaks workflow to PRs; added Dependabot config.

### Fixed
- **Friendly blocker names** — Sleep blocker display now uses friendly app names (e.g. "Google Chrome") rather than process names (e.g. "chrome_crashpad").

## [0.2.1] - 2026-03-10

### Added
- **Drift detection** — On popover open, Benzo reads `pmset -g` and re-applies settings if they've drifted from expected values (e.g., changed by another tool or macOS update). Only runs when deep sleep is active.

## [0.2.0] - 2026-03-10

### Added
- **Option-click diagnostics** — ⌥-click the menubar icon to see sleep sessions, wake reasons, USB devices, and settings verification. Four diagnostic panels built with `DiagnosticService.swift` parsing `pmset -g log` and `system_profiler SPUSBDataType`.
- **Sleep Now button** — Apply deep sleep settings and sleep immediately with one click. Activates Benzo first if not already active.
- **Quit restores defaults** — Quitting Benzo while active restores all original pmset settings from backup before terminating.
- **Build/notarize script** — `scripts/build-dmg.sh` archives, signs, notarizes (when credentials available), and packages as DMG. Outputs SHA256 for Homebrew.
- **Homebrew cask formula** — `Casks/benzo.rb` for `brew tap chrisrogers37/benzo && brew install --cask benzo`.
- **Landing page diagnostics mockup** — Alt+click the pill icon in the interactive mockup to see a sample diagnostic view. Hint text below mockup.
- **Gatekeeper bypass info tray** — Subtle pink pill on landing page: "macOS says 'unidentified developer'?" expands with `xattr` instructions.

### Fixed
- **Wake event pairing** — Diagnostic sleep sessions now use chronological index tracking instead of `.first(where:)`, which was incorrectly pairing wake events with wrong sleep events.
- **Single log parse** — Combined separate `fetchSleepSessions()` and `fetchLastWakeReason()` into a single `fetchSleepData()` call to avoid parsing `pmset -g log` twice.
- **Static wake reason mapper** — Extracted `SleepSession.humanReadableReason()` as a static method instead of constructing throwaway `SleepSession` objects in `DiagnosticView`.
- **Mobile responsive breakage** — Fixed landing page layout overflow and spacing issues at 375px and 768px breakpoints.

### Changed
- **Landing page copy** — Updated stale descriptions to match current app capabilities.
- **Version bump** — `MARKETING_VERSION` and footer updated from 0.1.0 to 0.2.0.

### Removed
- **Draft files** — Removed `benzo-prd.md` (draft PRD) and `benzo-final.jsx` (prototype) from repo.
- **GitHub Pages workflow** — Removed stale `.github/workflows/` deployment config; deploying via Vercel.

## [0.1.0] - 2026-02-10

### Added
- **Menubar app** — macOS menubar toggle for deep sleep (`hibernatemode 25`). Lives in the system tray with a pink pill icon.
- **Six pmset protections** — `hibernatemode 25`, `powernap 0`, `standby 0`, `autopoweroff 0`, `tcpkeepalive 0`, `proximitywake 0`.
- **Granular control** — Toggle individual pmset settings on/off from the Options panel.
- **One-click revert** — Original pmset values backed up on first activation, restored on deactivate.
- **Launch at login** — `SMAppService` integration for macOS 13+.
- **First-run setup** — Installs sudoers rule (`/etc/sudoers.d/benzo`) for passwordless pmset access.
- **Landing page** — React/Vite single-page site with interactive mockup of the app. Deployed on Vercel.
