#!/usr/bin/env bash
set -euo pipefail

# File system-review issues using only labels that already exist on the repo.
# (Cloud-agent token can create issues but cannot create labels/milestones.)
#
# Usage: ./file-issues-mapped.sh

REPO="${BENZO_REPO:-chrisrogers37/benzo}"
TRACKER="documentation/planning/system-review_2026-07-07/01_issue-tracker.md"
FOOTER="
---
**Milestone:** see title prefix / body.
Full context: \`${TRACKER}\` (system review 2026-07-07)."

create_issue() { # labels title body
    local labels="$1" title="$2" body="$3"
    gh issue create --repo "$REPO" --title "$title" --label "$labels" --body "${body}${FOOTER}"
}

echo "=== P0 individual issues ==="

# Note: #52 was a filing-access test (duplicate BZ-001) — close manually if desired.

create_issue "bug,priority:high" \
"BZ-001: Restore settings on all termination paths, not just the footer Quit button" \
"There is no \`applicationShouldTerminate\`/\`applicationWillTerminate\` in \`AppDelegate\` — the restore path only runs from the popover Quit button. Cmd+Q, logout, restart, Force Quit, \`kill\`, or a crash leave \`hibernatemode 25\` applied system-wide.

**Milestone:** M1 — Safety promise

**Fix:** implement \`applicationShouldTerminate\`, listen for \`NSWorkspace.willPowerOffNotification\`, reconcile at launch.

Files: \`Benzo/App/AppDelegate.swift\`, \`Benzo/ViewModels/BenzoViewModel.swift:117-122\`"

create_issue "bug,priority:high" \
"BZ-002: PMSetState parser is fragile and can write a corrupt backup that breaks restore" \
"Parsing splits each line on the first **space** only, but \`pmset -g\` output contains tabs, multi-word keys, section headers, and annotated values. Garbage entries land in the backup JSON and are rejected at restore time.

**Milestone:** M1 — Safety promise

**Fix:** parse \`pmset -g custom\`, split on all whitespace, strip parenthetical annotations, validate backup at save time. Add fixture tests (BZ-020).

Files: \`Benzo/Models/PMSetState.swift:7-18\`, \`Benzo/Services/BackupService.swift:15-18\`"

create_issue "bug,priority:high" \
"BZ-003: Deactivate with a missing/corrupt backup silently pretends success" \
"If \`BackupService.load()\` fails, \`deactivate()\` sets \`isActive = false\` and returns — UI says Deep Sleep is off while pmset may still be in hibernatemode 25.

**Milestone:** M1 — Safety promise

**Fix:** treat missing/corrupt backup as an error state; offer explicit \"restore macOS defaults\" fallback.

Files: \`Benzo/ViewModels/BenzoViewModel.swift:272-278\`"

create_issue "bug,priority:high" \
"BZ-004: quit() swallows restore failures with try?" \
"Both backup load and restore in \`quit()\` use \`try?\` — failures are invisible and the app terminates leaving modified settings.

**Milestone:** M1 — Safety promise

**Fix:** blocking alert on failure (Retry / Quit Anyway). Log failures (BZ-035).

Files: \`Benzo/ViewModels/BenzoViewModel.swift:117-122\`"

create_issue "bug,priority:high" \
"BZ-005: Partial pmset apply with no rollback" \
"\`applySettings\` applies keys sequentially; mid-loop failure leaves mixed system state with no rollback.

**Milestone:** M1 — Safety promise

**Fix:** snapshot before apply; rollback on failure.

Files: \`Benzo/Services/PMSetService.swift:24-51\`"

create_issue "priority:high,enhancement" \
"BZ-006: Notarization pipeline in build-dmg.sh is broken" \
"On export failure the script falls back to ad-hoc signing but still submits to notarization — Apple rejects and \`set -e\` kills the script before DMG creation. Also: missing teamID, unvalidated VERSION, no codesign verify gate.

**Milestone:** M2 — Frictionless install. Depends on BZ-007.

**Fix:** notarize only when Developer ID signature confirmed; skip with warning otherwise. See \`scripts/build-dmg.sh\`."

create_issue "priority:high,enhancement" \
"BZ-007: No hardened runtime or entitlements configured" \
"No \`.entitlements\`, no \`ENABLE_HARDENED_RUNTIME\`. Blocks notarization (BZ-006).

**Milestone:** M2 — Frictionless install

Files: \`Benzo/Benzo.xcodeproj/project.pbxproj\`"

create_issue "priority:high,documentation" \
"BZ-008: No LICENSE file; license strategy undecided for monetization" \
"README claims MIT but no LICENSE file. Strategic gate for revenue — see \`02_roadmap-to-revenue.md\` §M3.

**Milestone:** M3 — Monetization"

echo "=== P1 individual issues ==="

create_issue "bug,priority:high" \
"BZ-009: isActive is never reconciled with real pmset state at launch" \
"\`isActive\` from UserDefaults; drift correction only on popover open.

**Milestone:** M1 — Safety promise

**Fix:** reconcile on launch and wake notifications.

Files: \`Benzo/ViewModels/BenzoViewModel.swift:36-67, 192-226\`"

create_issue "bug,enhancement" \
"BZ-010: toggleSetting doesn't revert the checkbox when apply fails" \
"State mutates before shell call; \`// Revert toggle\` comment has no code.

**Milestone:** M1 — Safety promise

Files: \`Benzo/ViewModels/BenzoViewModel.swift:93-98, 291-303\`"

create_issue "bug,enhancement" \
"BZ-011: All shell execution blocks the calling (main) thread" \
"\`Process.waitUntilExit()\` on main thread freezes popover during sudo+pmset.

**Milestone:** M1 — Safety promise

Files: \`Benzo/Services/ShellExecutor.swift:90-115\`"

create_issue "security,enhancement" \
"BZ-012: Silent sudoers reinstall at launch triggers unexplained admin prompt" \
"Init fires \`try? installSudoersRule()\` without user action.

**Milestone:** M2 — Frictionless install

Files: \`Benzo/ViewModels/BenzoViewModel.swift:62-66\`"

create_issue "bug,enhancement" \
"BZ-013: Master toggle can be On while applying nothing" \
"Empty enabled list still sets \`isActive = true\`.

**Milestone:** M1 — Safety promise

Files: \`Benzo/ViewModels/BenzoViewModel.swift:252-263\`"

create_issue "bug,priority:high" \
"BZ-014: Backup is only captured once, so re-activation can restore stale values" \
"Backup written only when \`!hasBackup()\`.

**Milestone:** M1 — Safety promise

Files: \`Benzo/ViewModels/BenzoViewModel.swift:254-258\`"

create_issue "bug,enhancement" \
"BZ-015: Non-admin users pass setup but every pmset call fails" \
"Sudoers grants NOPASSWD to \`%admin\` only.

**Milestone:** M2 — Frictionless install

Files: \`Benzo/Services/ShellExecutor.swift:82-84\`"

create_issue "bug,priority:high" \
"BZ-016: Scheduled sleep timer survives deactivate/quit and re-activates the app" \
"\`cancelScheduledSleep()\` not called from deactivate/quit.

**Milestone:** M1 — Safety promise

Files: \`Benzo/ViewModels/BenzoViewModel.swift:160-188, 272-289\`"

create_issue "bug,priority:high,documentation" \
"BZ-017: README Homebrew tap instructions point to a repo that doesn't exist" \
"\`brew tap chrisrogers37/benzo\` → 404.

**Milestone:** M2 — Frictionless install

Files: \`README.md:15-19\`"

create_issue "priority:high,github_actions" \
"BZ-018: No release automation (tag → DMG → GitHub release → cask bump)" \
"Fully manual releases.

**Milestone:** M2 — Frictionless install"

create_issue "github_actions" \
"BZ-019: CI never compiles anything — broken Swift or JSX can merge to main" \
"Only npm audit + gitleaks run today.

**Milestone:** M2 — Frictionless install"

create_issue "tech-debt,priority:medium" \
"BZ-020: Zero tests; parsing and sudoers generation are untested" \
"No test target. Highest-risk logic is untested.

**Milestone:** M1 — Safety promise. Land with BZ-002."

create_issue "bug,enhancement" \
"BZ-021: Social preview image 404s in production" \
"\`og-image.png\` referenced but missing from \`public/\`.

**Milestone:** M3 — Monetization

Files: \`index.html:13,19\`"

create_issue "bug,documentation" \
"BZ-022: pmset -a silently changes sleep behavior for every user on the Mac" \
"System-wide writes with no UI/docs warning on shared Macs.

**Milestone:** M2 — Frictionless install"

echo "=== M3 P2 individual issues ==="

create_issue "enhancement,security" \
"BZ-034: No uninstall story; sudoers rule lives forever" \
"\`removeSudoersRule()\` never called; cask uninstall can't delete root-owned sudoers.

**Milestone:** M3 — Monetization"

create_issue "enhancement,priority:medium" \
"BZ-035: No structured logging or crash reporting" \
"Restore/sudo/parse failures invisible for support.

**Milestone:** M3 — Monetization"

create_issue "enhancement,priority:medium" \
"BZ-036: No auto-update mechanism (Sparkle)" \
"No appcast; stale installs keep old sudoers rules. Depends on BZ-018.

**Milestone:** M3 — Monetization"

echo "=== Umbrella / clustered issues (P2/P3) ==="

create_issue "bug,enhancement" \
"Umbrella: Diagnostics correctness pass (BZ-024, BZ-029, BZ-030, BZ-032, BZ-050)" \
"Cluster fix with shared log fixtures:
- BZ-024 verification shows green when inactive
- BZ-029 fragile sleep-log parsing
- BZ-030 wake reason false positive on \"User\"
- BZ-032 USB panel empty on Apple Silicon
- BZ-050 diagnostics errors collapse to empty arrays"

create_issue "bug,enhancement" \
"Umbrella: Sleep lifecycle & app behavior fixes (BZ-023, BZ-025–028, BZ-031)" \
"- BZ-023 cancellable sleepNow delay (pairs with BZ-016)
- BZ-025 missing backup keys silently skipped on disable
- BZ-026 pkill caffeinate kills all user caffeinate
- BZ-027 launch-at-login toggle not reverted on failure
- BZ-028 global click monitor leaks
- BZ-031 Apple Silicon vs Intel hibernation differences"

create_issue "security,tech-debt" \
"Umbrella: Security hardening follow-ups (BZ-033, BZ-042)" \
"- BZ-033 backup file permissions + integrity
- BZ-042 audit Phase 02 (.env gitignore, Vite major upgrade)"

create_issue "enhancement,priority:medium" \
"Umbrella: Landing page quality pass (BZ-038–041, BZ-043, BZ-053, BZ-054)" \
"- BZ-041 Catalina vs Ventura copy
- BZ-039 accessibility
- BZ-040 SEO
- BZ-043 mockup sync (5 gaps)
- BZ-038 decompose BenzoHybrid.jsx
- BZ-053 vercel.json
- BZ-054 deep download link, self-host fonts, notarization copy"

create_issue "tech-debt,priority:medium" \
"Umbrella: Swift codebase debt burn-down (BZ-037, BZ-044–049, BZ-051, BZ-052)" \
"- BZ-037 god object + DI
- BZ-044 hardcoded version in footer
- BZ-045 force unwraps
- BZ-046 dead code
- BZ-047 misleading userCancelled catches
- BZ-048 empty Settings scene
- BZ-049 icon color drift
- BZ-051 build number hygiene
- BZ-052 package.json version drift"

echo ""
echo "=== All issues filed ==="
