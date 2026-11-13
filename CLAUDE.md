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
│   ├── SleepSetting.swift       — managed settings and exact key/value domains
│   ├── PMSetState.swift         — flat diagnostic parser and strict profile capture
│   ├── ControlState.swift       — checking, off, applying, verified, restoring, recovery
│   ├── RecoveryJournal.swift    — per-profile captured originals and operation evidence
│   ├── OriginalSettingsBackup.swift — legacy flat-backup decoder
│   ├── SleepSession.swift       — sleep/wake event with duration, battery delta, wake reason
│   └── USBDevice.swift          — USB device name and power draw
├── Services/
│   ├── PMSetService.swift       — fixed pmset capture request and target mapping
│   ├── RecoveryTransport.swift  — unprivileged reads and authenticated exact-cell helper writes
│   ├── HelperServiceClient.swift — explicit SMAppService setup, enrollment and replacement
│   ├── HelperEngine.swift       — enrolled-account admission, revisions and durable execution
│   ├── HelperIdentity.swift     — exact Developer ID identities and local UID/GeneratedUID
│   ├── CommandRunner.swift      — bounded process transport and owned-fixture tests
│   ├── OperationCoordinator.swift — serialized apply, restore, conflict and admission
│   ├── DurableJournal.swift    — checked account-local recovery evidence and lock
│   ├── ExecutionFenceStore.swift — persistent potentially-executed request fence
│   ├── BootIdentityProvider.swift — validated kernel boot identity
│   ├── PermissionObservation.swift — metadata-only legacy-rule evidence, never readiness
│   ├── BackupService.swift      — legacy flat-backup decoding only
│   └── DiagnosticService.swift  — bounded injected reads; parses logs/USB and observes settings
├── ViewModels/
│   └── BenzoViewModel.swift     — frozen selection, control/recovery state and diagnostics
├── Views/
│   ├── PopoverContentView.swift — main layout, switches between setup/normal/diagnostic views
│   ├── MasterToggleView.swift   — truthful control/recovery state and gated toggle
│   ├── SleepNowButton.swift     — disabled sleep action with recovery explanation
│   ├── SettingRowView.swift     — individual setting checkbox row
│   ├── FooterView.swift         — launch at login, version, restore defaults, quit
│   ├── SetupView.swift          — explicit helper approval, account enrollment and readiness
│   └── DiagnosticView.swift     — ⌥-click view: sleep sessions, wake reason, USB, observed settings
└── Theme/
    └── BenzoTheme.swift         — colors (accent: #d4749c)

src/BenzoHybrid.jsx              — unbundled historical page; legacy layout/copy only
src/components/BenzoMockup.jsx   — unbundled historical mockup and tests
src/landing/NativeAppDemo.jsx      — source-based interactive reproduction; original mockup retained as historical source
src/landing/BenzoLanding.jsx         — public landing page; single owner of interactive demo state
src/design/                     — core web tokens, CSS, copy, metadata, icons and app presentation
src/demo/                       — browser state/hooks and legacy compatibility fixture exports
Benzo/BenzoHelper/               — root daemon entry point, private authority store and bundled launchd plist
Benzo/BenzoTests/                — unhosted injected tests plus owned read-child/storage fixtures
scripts/build-dmg.sh             — archive, sign, notarize, and package as DMG
Casks/benzo.rb                   — Homebrew cask formula
```

### Key Principles

- **Mockup sync**: Any UI or behavioral change to the native app must also be reflected in `src/landing/NativeAppDemo.jsx`, `src/demo/useBenzoDemo.js` and `src/design/appPresentation.js`. `BenzoLanding` owns the single state. Preserve historical `BenzoHybrid`/`BenzoMockup` sources, reducer and tests.
- **Draft fidelity**: Marketing redesigns must preserve the native UI and interactive controls in `src/landing/NativeAppDemo.jsx`; keep demo navigation/disclosures outside the app panel. Verify against current Swift source, and reserve pixel-parity claims for comparison with an approved native screenshot.
- **Core web design**: Import redesigned page/demo presentation from `src/design/`. Keep one `useBenzoDemo` state in `BenzoLanding` for panel and page theme; never mirror the master switch in a second state. Marketing copy and native UI copy have separate owners inside the module. See `src/design/README.md`.
- **Recovery scope**: Manual apply captures immutable originals per reported profile and freezes selections. A setting is unavailable if any required key is absent from a reported profile. Off, System Defaults and quit attempt to restore the exact captured pre-Benzo values; System Defaults is not Apple's factory reset. Sleep Now remains unavailable. Readback establishes reported settings only; it cannot prove physical sleep, hibernation or USB behavior. Conflicts offer Keep Current, Restore Recorded Original Anyway or Defer. Same-boot execution uncertainty blocks further writes even if reads match; a verified later boot permits read-only reconciliation, never replay or automatic restore. Legacy flat originals remain untrusted for profile mapping; legacy recovery and rule retirement require administrator-assisted steps outside the app.
- **Helper authorization**: The November 13 amendment `08_helper-authorization.md` replaces repeated AppleScript prompts with an app-bundled SMAppService daemon. Only the local account completing setup is enrolled, bound to UID plus GeneratedUID. Both peers require exact Developer ID identities and role entitlements. The helper accepts no paths or shell command input. Root-owned authority/revisions/fences supplement the GUI recovery journal; lost replies never permit replay. Unsigned CI artifacts cannot use this transport. Explicit replacement requires resolved settings, a helper admission pause, asynchronous unregister completion, and a matching embedded helper code hash. Do not silently transfer ownership or erase evidence.
- **Not App Store**: Benzo requires root access for pmset, incompatible with App Store sandboxing.

---

## Development Workflow

1. Make changes
2. Compile Debug and Release with full Xcode; CI must run unhosted `BenzoCoreTests`. Command Line Tools-only checks are not XCTest. Native acceptance on this host is limited to the user's scoped task authorization.
3. Use Node 24 from `.nvmrc`; run `npm ci`, `npm test`, `npm run build`, and authorized browser checks with `npm run dev`.
4. Before declaring a PR ready: verify both app configurations, core tests, site tests/build and browser parity; record blocked checks explicitly. The owner authorized reviewed merges of the ordered recovery fixes on November 3.

PRs run web/native build and test checks (`.github/workflows/build.yml`) plus `npm audit --audit-level=moderate` and Gitleaks (`.github/workflows/security.yml`). All required checks and independent review must pass before merge.

This Mac Mini is an always-on fleet host. The November 4 recovery task is authorized to build and launch that task's app, exercise temporary selected-setting apply/restore with administrator prompts, relaunch and quit. It does not authorize sleep/reboot, permission-rule or login-item changes, installation/removal, or terminating other fleet processes. Core tests use injected dependencies; the bounded runner fixture never proves live authorization or hardware outcomes. Full-Xcode CI and native acceptance remain separate evidence. Vercel can auto-deploy branch previews. The current recovery task authorizes branch pushes and associated previews; routine pushes do not need repeated permission. Do not push main directly. No public release is authorized by implementation or CI completion alone; the latest public version remains 0.3.0.

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

- **GitHub Releases** — the upcoming helper release requires Developer ID signing and notarization. Membership is deferred during source development; no ad-hoc fallback can enable the helper. Packaging integration and signed native acceptance remain required before release.
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
