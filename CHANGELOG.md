# Changelog

All notable changes to Benzo are documented here.

## [Unreleased]

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
