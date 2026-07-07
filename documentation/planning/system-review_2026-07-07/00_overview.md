# Benzo Full System Review — 2026-07-07

Status: **Complete** — findings triaged into [`01_issue-tracker.md`](01_issue-tracker.md), plan in [`02_roadmap-to-revenue.md`](02_roadmap-to-revenue.md).

## Scope

Every Swift source file (20 files under `Benzo/Benzo/`), `project.pbxproj`, `Info.plist`,
the entire landing page (`src/`, `index.html`, Vite/npm config), `scripts/build-dmg.sh`,
`Casks/benzo.rb`, `.github/` CI, and all documentation (`README.md`, `CHANGELOG.md`,
`documentation/`, `.claude/`). Release state verified against the live GitHub release
and Homebrew tap.

## Project direction (as documented)

Benzo is a **free, open-source macOS menubar utility** that forces true hibernation
(`hibernatemode 25`) so dock-plugged MacBooks actually power off. Distribution is
deliberately **outside the App Store** (requires root `pmset` access via a sudoers rule).
The React/Vite landing page on Vercel doubles as an interactive mockup that must stay
in sync with the native app.

History: 0.1.0 (Feb 2026, core app + landing page) → 0.2.0/0.2.1 (Mar, diagnostics,
quit-restore, drift detection, DMG script, cask) → 0.3.0 (Jun, timed sleep, sleep
blockers, sudoers hardening, security CI). A security audit (Mar 2026) completed
Phase 01 (shell hardening); **Phase 02 (env hygiene + Vite major upgrade) was planned
but never done**.

## Current state, honestly assessed

**This is already a downloadable product.** `Benzo-0.3.0.dmg` is live on GitHub
Releases and the cask sha256 matches. What it is **not** yet is a product someone
would pay for:

1. **The core safety promise has holes.** "Quit restores your pmset settings" is only
   true when the user clicks the footer Quit button. Cmd+Q, logout, restart, Force
   Quit, or a crash leave `hibernatemode 25` applied system-wide with no restore and
   no launch-time reconciliation. The `pmset -g` parser is fragile enough to write a
   corrupt backup, which then makes restore fail. Several failure paths use `try?` and
   fail silently. For an app whose entire value proposition is "safely change dangerous
   system settings and always put them back," these are the highest-priority defects.
2. **Distribution has Gatekeeper friction.** The DMG is unsigned/un-notarized; users
   must right-click-open or strip quarantine. The `brew tap chrisrogers37/benzo`
   instructions in the README point to a repo that returns 404. The build script's
   notarization path is broken (submits ad-hoc-signed builds, aborts before DMG).
3. **No safety net.** Zero tests, no Swift build in CI, no release automation, no
   crash reporting, no auto-update. CI only runs `npm audit` + gitleaks.
4. **Marketing surface has gaps.** Broken og-image (404 in production), no LICENSE
   file despite the README claiming MIT, landing copy says "Catalina+" while the app
   requires Ventura 13+, no analytics, no direct download link.

## Review verdict

Code quality is above average for a solo project — argv-based `Process` execution,
`visudo`-validated sudoers allowlist, atomic backup writes, drift detection. The
architecture problems are conventional and fixable: a god-object view model, static
service enums that block testing, main-thread shell calls, and a 1,370-line landing
page monolith.

The path to revenue is not "add features" — it is **(a) make the safety promise
bulletproof, (b) remove all install friction via signing + notarization, (c) add a
license/payment layer**. See the roadmap.

## Triage counts

| Priority | Count | Meaning |
|----------|-------|---------|
| P0 | 8 | Breaks the core safety promise or blocks paid distribution |
| P1 | 14 | High-impact bugs, security gaps, release blockers |
| P2 | 20 | Medium bugs, tech debt, UX/SEO/a11y gaps |
| P3 | 12 | Polish, dead code, doc drift |

Issues use IDs `BZ-001`…`BZ-054` so they can be copied 1:1 into GitHub issues
(suggested labels included per item). This markdown tracker is the source of truth
until they are filed.
