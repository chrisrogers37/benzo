# Changelog

All notable changes to Benzo are documented here.

## [Unreleased]

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
