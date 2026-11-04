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

**Benzo** is a macOS menubar sleep-configuration utility. Applying a pmset value is not proof of physical hibernation or USB power behavior. The landing page is React/Vite on Vercel. The accepted scope and execution order live in `documentation/planning/tech_debt/benzo-remediation_2026-11-02/00_TECH_DEBT.md`: 03 → 01 → 04 → conditional 02. Earlier reorientation documents remain safety references, not authority to restore removed features.

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
│   ├── ShellExecutor.swift      — legacy synchronous mutation transport; unreleased
│   ├── CommandRunner.swift      — bounded fixed diagnostic reads and owned-fixture tests
│   ├── PermissionObservation.swift — metadata-only legacy-rule evidence, never readiness
│   ├── BackupService.swift      — save/load original pmset values to ~/Library/Application Support/Benzo/
│   └── DiagnosticService.swift  — bounded injected reads; parses logs/USB and observes settings
├── ViewModels/
│   └── BenzoViewModel.swift     — state: legacy apply/restore/quit, disabled sleep action, diagnostic results
├── Views/
│   ├── PopoverContentView.swift — main layout, switches between setup/normal/diagnostic views
│   ├── MasterToggleView.swift   — "Deep Sleep is On/Off" header with toggle
│   ├── SleepNowButton.swift     — disabled sleep action with recovery explanation
│   ├── SettingRowView.swift     — individual setting checkbox row
│   ├── FooterView.swift         — launch at login, version, restore defaults, quit
│   ├── SetupView.swift          — non-authorizing permission observation, Refresh and Back
│   └── DiagnosticView.swift     — ⌥-click view: sleep sessions, wake reason, USB, observed settings
└── Theme/
    └── BenzoTheme.swift         — colors (accent: #d4749c)

src/BenzoHybrid.jsx              — unbundled historical page; legacy layout/copy only
src/components/BenzoMockup.jsx   — unbundled historical mockup and tests
src/landing/NativeAppDemo.jsx      — source-based interactive reproduction; original mockup retained as historical source
src/landing/BenzoLanding.jsx         — public landing page; single owner of interactive demo state
src/design/                     — core web tokens, CSS, copy, metadata, icons and app presentation
src/demo/                       — browser state/hooks and legacy compatibility fixture exports
Benzo/BenzoTests/                — unhosted injected tests plus owned read-child fixture
scripts/build-dmg.sh             — archive, sign, notarize, and package as DMG
Casks/benzo.rb                   — Homebrew cask formula
```

### Key Principles

- **Mockup sync**: Any UI or behavioral change to the native app must also be reflected in `src/landing/NativeAppDemo.jsx`, `src/demo/useBenzoDemo.js` and `src/design/appPresentation.js`. `BenzoLanding` owns the single state. Preserve historical `BenzoHybrid`/`BenzoMockup` sources, reducer and tests.
- **Draft fidelity**: Marketing redesigns must preserve the native UI and interactive controls in `src/landing/NativeAppDemo.jsx`; keep demo navigation/disclosures outside the app panel. Verify against current Swift source, and reserve pixel-parity claims for comparison with an approved native screenshot.
- **Core web design**: Import redesigned page/demo presentation from `src/design/`. Keep one `useBenzoDemo` state in `BenzoLanding` for panel and page theme; never mirror the master switch in a second state. Marketing copy and native UI copy have separate owners inside the module. See `src/design/README.md`.
- **Recovery scope**: Containment removes automatic/timed writes and freezes selections while active or recovery evidence is present/unknown. Sleep Now is unavailable. Legacy manual apply/restore/quit still have known failure paths, held for 02 or an accepted recovery-only endpoint. Never claim an Off toggle proves restoration or release an incomplete native safety slice. Preserve originals and grants during app removal; removal is not verified restoration or retirement.
- **Not App Store**: Benzo requires root access for pmset, incompatible with App Store sandboxing.

---

## Development Workflow

1. Make changes
2. Compile Debug and Release with full Xcode, without launching the app; run the unhosted `BenzoCoreTests` scheme. Use README commands and task-owned DerivedData.
3. Use Node 24 from `.nvmrc`; run `npm ci`, `npm test`, `npm run build`, and authorized browser checks with `npm run dev`.
4. Before declaring a PR ready: verify both app configurations, core tests, site tests/build and browser parity; record blocked checks explicitly. The owner authorized reviewed merges of the ordered recovery fixes on November 3.

PRs run web/native build and test checks (`.github/workflows/build.yml`) plus `npm audit --audit-level=moderate` and Gitleaks (`.github/workflows/security.yml`). All required checks and independent review must pass before merge.

This Mac Mini is an always-on fleet host: never launch production Benzo or mutate its power, sudoers, login or fleet state for acceptance. Core tests compile injected services/models/ViewModel and fake dependencies. The bounded process engine may run only its owned synthetic fixture; live adapters and app composition remain excluded. Dedicated native acceptance is separately approved. Vercel can auto-deploy branch previews: obtain scoped deployment authority before remote push. Do not push main directly. The owner authorized reviewed recovery-phase merges and a native release only after the recovery fixes and acceptance are complete.

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
./scripts/build-dmg.sh --help  # Explicit mode/output; Developer ID uses a configured keychain profile
bash scripts/tests/build-dmg-test.sh  # Stub-only packaging regressions; no live Apple tools
```

## Code Style & Conventions

- SwiftUI for all views, `@ObservedObject`/`@Published` for state
- Pink accent `#d4749c` throughout — see `BenzoTheme.swift`
- Draft fonts: system sans for reading; system mono for technical values. Typography and styling live in `src/design/`, without a CSS framework.
- The public `/` route uses the approved design and system fonts; `/draft` redirects to it. Historical page files remain unbundled, and their old copy is not approved product guidance. Site publication does not complete broader P8/native acceptance.
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
- Existing releases installed a legacy rule at `/etc/sudoers.d/benzo`. The current source only observes metadata at the canonical `/private/etc/sudoers.d/benzo` path. Presence never proves authorization or safe scope. Installer, remover, version-based readiness and privileged probe paths are removed; preserve old evidence and grants until reviewed recovery/retirement.

### Distribution

- **Selected release mode (November 4, 2026)** — the owner selected GitHub distribution of an explicitly unnotarized community build; no Developer ID is available. An ad-hoc signature establishes neither Developer ID identity, Apple notarization nor Gatekeeper acceptance. Do not make Apple Developer membership a blocker for this selected mode.
- **Community candidate CI** — after native tests/archive checks, the existing full-Xcode `build` job runs `build-dmg.sh --mode community` in a unique new output directory. Only the DMG, `SHA256SUMS` and `artifact.txt` are uploaded as `benzo-community-candidate` for 7 days. It preserves the source version/build and does not publish a release. Recovery/artifact acceptance and final version/checksum metadata precede publication.
- **Native packaging** — `scripts/build-dmg.sh --mode community|developer-id --output-dir <new-absolute-dir>`; see README for the build number and Developer ID identity/team/keychain-profile arguments. Full Xcode is required. Developer ID mode uploads to Apple, requires Accepted results and validated app/DMG staples, and never downgrades on failure. Community mode is explicitly ad-hoc signed and unnotarized. No mode is selected implicitly and neither mode publishes a release.
- **Future Developer ID target** — revisit only when broader distribution/support needs justify it. Securely configure the certificate/team and notary keychain profile on the selected signing Mac, then use the existing explicit Developer ID mode. Real signature/runtime, Accepted/staple/Gatekeeper and clean-Mac installation/launch evidence must support the resulting trust claim. See README; no credential, updater or release-platform work is implied now.
- **Artifact evidence** — actual version/build, universal slices and signatures are checked before final output. `artifact.txt` and `SHA256SUMS` describe the final DMG. Fixture tests do not establish real signing, installation or native recovery acceptance. Release publication remains gated on those outcomes.
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
