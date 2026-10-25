# CLAUDE.md - Benzo

This file provides project-specific guidance for Claude Code. Update this file whenever Claude does something incorrectly so it learns not to repeat mistakes.

---

## Workflow Orchestration

### Plan Mode Default
- Enter plan mode for ANY non-trivial task (3+ steps or architectural decisions)
- If something goes sideways, STOP and re-plan immediately – don't keep pushing
- Use plan mode for verification steps, not just building
- Write detailed specs upfront to reduce ambiguity

### Subagent Strategy
- Use subagents liberally to keep main context window clean
- Offload research, exploration, and parallel analysis to subagents
- For complex problems, throw more compute at it via subagents
- One task per subagent for focused execution

### Verification Before Done
- Never mark a task complete without proving it works
- Diff behavior between main and your changes when relevant
- Ask yourself: "Would a staff engineer approve this?"
- Run tests, check logs, demonstrate correctness

### Core Principles
- **Simplicity First**: Make every change as simple as possible. Impact minimal code.
- **No Laziness**: Find root causes. No temporary fixes. Senior developer standards.
- **Minimal Impact**: Changes should only touch what's necessary. Avoid introducing bugs.
- **Demand Elegance** (Balanced):
  - For non-trivial changes: pause and ask "is there a more elegant way?"
  - If a fix feels hacky: "Knowing everything I know now, implement the elegant solution"
  - Skip this for simple, obvious fixes — don't over-engineer
  - Challenge your own work before presenting it

### Autonomous Bug Fixing
- When given a bug report: just fix it. Don't ask for hand-holding
- Go fix failing CI tests without being told how

---

## Project Overview

**Benzo** is a macOS menubar sleep-configuration utility. Applying a pmset value is not proof of physical hibernation or USB power behavior. The landing page is React/Vite on Vercel. The approved re-orientation and delivery gates live in `documentation/plans/benzo-reorientation_2026-10-25/00_overview.md`.

**Version**: 0.3.0

### Architecture

```
Benzo/Benzo/                     — Swift macOS menubar app
├── App/
│   ├── BenzoApp.swift           — SwiftUI entry point, creates AppDelegate
│   └── AppDelegate.swift        — NSStatusItem, popover, ⌥-click diagnostics, dynamic icon
├── Models/
│   ├── SleepSetting.swift       — enum of pmset settings (keys, labels, defaults)
│   ├── PMSetState.swift         — parses `pmset -g` output into key-value pairs
│   ├── OriginalSettingsBackup.swift — Codable struct for persisted backup
│   ├── SleepSession.swift       — sleep/wake event with duration, battery delta, wake reason
│   └── USBDevice.swift          — USB device name and power draw
├── Services/
│   ├── PMSetService.swift       — runs pmset commands via ShellExecutor
│   ├── ShellExecutor.swift      — sudo via sudoers rule (post-setup) or osascript (first run)
│   ├── BackupService.swift      — save/load original pmset values to ~/Library/Application Support/Benzo/
│   └── DiagnosticService.swift  — parses pmset logs, system_profiler, verifies settings
├── ViewModels/
│   └── BenzoViewModel.swift     — all state: activate/deactivate, sleepNow, quit (restores defaults), diagnostics
├── Views/
│   ├── PopoverContentView.swift — main layout, switches between setup/normal/diagnostic views
│   ├── MasterToggleView.swift   — "Deep Sleep is On/Off" header with toggle
│   ├── SleepNowButton.swift     — pink capsule button, activates settings then sleeps
│   ├── SettingRowView.swift     — individual setting checkbox row
│   ├── FooterView.swift         — launch at login, version, restore defaults, quit
│   ├── SetupView.swift          — first-run permission grant screen
│   └── DiagnosticView.swift     — ⌥-click view: sleep sessions, wake reason, USB, verification
└── Theme/
    └── BenzoTheme.swift         — colors (accent: #d4749c)

src/BenzoHybrid.jsx              — marketing wrapper and shared demo state
src/components/BenzoMockup.jsx   — interactive mockup; keep native UI parity here
src/demo/                       — pure reducer and demonstration fixtures
Benzo/BenzoTests/                — unhosted core XCTest bundle; fakes only
scripts/build-dmg.sh             — archive, sign, notarize, and package as DMG
Casks/benzo.rb                   — Homebrew cask formula
```

### Key Principles

- **Mockup sync**: Any UI or behavioral change to the native app must also be reflected in `src/components/BenzoMockup.jsx` and the shared demo state in `src/BenzoHybrid.jsx` / `src/demo/`.
- **Recovery scope**: The current app attempts backup restoration on quit, with known failure paths tracked in P4/P5. Never claim defaults or successful restoration without evidence.
- **Not App Store**: Benzo requires root access for pmset, incompatible with App Store sandboxing.

---

## Development Workflow

1. Make changes
2. Compile Debug and Release with full Xcode, without launching the app; run the unhosted `BenzoCoreTests` scheme. Use README commands and task-owned DerivedData.
3. Use Node 24 from `.nvmrc`; run `npm ci`, `npm test`, `npm run build`, and authorized browser checks with `npm run dev`.
4. Before declaring a PR ready: verify both app configurations, core tests, site tests/build and browser parity; record blocked checks explicitly. User merges each ordered phase.

PRs run web/native build and test checks (`.github/workflows/build.yml`) plus `npm audit --audit-level=moderate` and Gitleaks (`.github/workflows/security.yml`). All required checks and independent review must pass before merge.

This Mac Mini is an always-on fleet host: never launch production Benzo or mutate its power, sudoers, login or fleet state for acceptance. Core tests compile only injected services/models/ViewModel and fake dependencies; they must not link live adapters or app composition. Dedicated native acceptance is separately approved. Vercel can auto-deploy branch previews: obtain scoped deployment authority before remote push. Never push main or merge.

## Commands Reference

```sh
# Native app
xcodebuild -project Benzo/Benzo.xcodeproj -scheme Benzo -configuration Debug build    # Debug build
xcodebuild -project Benzo/Benzo.xcodeproj -scheme Benzo -configuration Release build  # Release build

# Landing page
npm ci               # Exact lockfile install on Node 24 (.nvmrc)
npm test             # Vitest / React Testing Library / jsdom
npm run dev          # Dev server
npm run build        # Production build

# Distribution
./scripts/build-dmg.sh   # Build DMG (set APPLE_ID, APPLE_TEAM_ID, APP_PASSWORD for notarization)
```

## Code Style & Conventions

- SwiftUI for all views, `@ObservedObject`/`@Published` for state
- Pink accent `#d4749c` throughout — see `BenzoTheme.swift`
- Fonts: Instrument Sans (body), IBM Plex Mono (code) on landing page
- Landing page uses inline React styles, no CSS framework
- New `.swift` files must be registered in `project.pbxproj` in 4 places:
  1. `PBXBuildFile` section
  2. `PBXFileReference` section
  3. `PBXGroup` section (appropriate group: Views, Models, etc.)
  4. `PBXSourcesBuildPhase` section

## Things Claude Should NOT Do

- Don't add Swift files without registering them in `project.pbxproj` (4 sections)
- Don't change native app UI without updating the landing page mockup
- Don't use `womp` for USB wake — it's Wake-on-LAN (network wake) only
- Do not infer physical USB power behavior or hibernation from a pmset value; use declared hardware/OS evidence.
- Don't forget the brief window between `pmset sleepnow` and full hibernation where USB devices could still wake the Mac

## Project-Specific Patterns

### pmset Learnings

- `womp` = Wake-on-LAN (network wake), NOT physical USB device wake. Labeled "Disable Network Wake" in the app.
- Do not promise USB wake prevention or zero power drain from `hibernatemode 25`; supported hardware/OS behavior must be observed separately.
- Between `pmset sleepnow` and full hibernation, there's a brief window where the Mac is in normal sleep and USB devices could still wake it.
- The sudoers rule (`/etc/sudoers.d/benzo`) grants passwordless access to a narrow allowlist of `pmset` invocations only: `pmset sleepnow` and `pmset -a <key> [0-9]*` for the keys defined in `SleepSetting.allCases.flatMap(\.pmsetKeys)`. Generated at install time from `SleepSetting`, validated with `visudo -cf` before install, versioned via `sudoersRuleVersion` in `UserDefaults` for migration.

### Distribution

- **GitHub Releases** — signed `.dmg` (notarized when Apple Developer credentials are available)
- **Homebrew** — `brew install --cask benzo` (personal tap; official homebrew-cask tap requires notarized DMG)
- Gatekeeper bypass: right-click → Open, or `xattr -d com.apple.quarantine /Applications/Benzo.app`
- Vercel Git integration can deploy previews on branch pushes and production on main; deployment remains separately approved.

---

## Self-Improvement Loop

After ANY correction from the user:
1. Acknowledge the correction
2. Update `.claude/lessons.md` with the pattern
3. Write rules that prevent the same mistake
4. Review lessons at session start for this project

## Task Management

1. **Plan First**: Write plan to `.claude/todo.md` with checkable items
2. **Verify Plan**: Check in before starting implementation
3. **Track Progress**: Mark items complete as you go
4. **Explain Changes**: High-level summary at each step
5. **Document Results**: Add review section to `.claude/todo.md`
6. **Capture Lessons**: Update `.claude/lessons.md` after corrections

---

_Update this file continuously. Every mistake Claude makes is a learning opportunity._
_After corrections, also update `.claude/lessons.md`._
