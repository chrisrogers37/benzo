#!/usr/bin/env bash
set -euo pipefail

# File the 2026-07-07 system-review findings as GitHub issues.
# See 03_issue-filing-plan.md for the mapping rationale.
#
# Usage:
#   DRY_RUN=1 ./file-issues.sh   # preview, no GitHub writes
#   ./file-issues.sh             # create labels, milestones, and 30 issues
#
# Requires: gh CLI authenticated with write access to the repo.
# Issues are NOT deduplicated — run the creation once.

REPO="${BENZO_REPO:-chrisrogers37/benzo}"
TRACKER="documentation/planning/system-review_2026-07-07/01_issue-tracker.md"
DRY_RUN="${DRY_RUN:-0}"

M1="M1 — Safety promise"
M2="M2 — Frictionless install"
M3="M3 — Monetization"

command -v gh >/dev/null 2>&1 || { echo "error: gh CLI not found" >&2; exit 1; }

ensure_label() { # name color description
    if [ "$DRY_RUN" = "1" ]; then
        echo "[dry-run] label: $1"
    else
        gh label create "$1" --repo "$REPO" --color "$2" --description "$3" --force
    fi
}

ensure_milestone() { # title description
    if [ "$DRY_RUN" = "1" ]; then
        echo "[dry-run] milestone: $1"
    else
        gh api "repos/$REPO/milestones" -f title="$1" -f description="$2" >/dev/null \
            || echo "  note: milestone '$1' may already exist — continuing"
    fi
}

create_issue() { # title labels milestone body
    local title="$1" labels="$2" milestone="$3" body="$4"
    body="${body}

---
Full context: \`${TRACKER}\` (system review 2026-07-07)."
    if [ "$DRY_RUN" = "1" ]; then
        echo "[dry-run] issue: $title  [labels: $labels] [milestone: ${milestone:-—}]"
        return
    fi
    local args=(--repo "$REPO" --title "$title" --label "$labels" --body "$body")
    [ -n "$milestone" ] && args+=(--milestone "$milestone")
    gh issue create "${args[@]}"
}

echo "=== Ensuring labels ==="
ensure_label "safety"          "b60205" "Breaks the restore-your-settings promise"
ensure_label "release-blocker" "d93f0b" "Blocks a signed, paid public release"
ensure_label "bug"             "d73a4a" "Something isn't working"
ensure_label "security"        "e11d21" "Security hardening"
ensure_label "build"           "c5def5" "Xcode project / DMG / signing pipeline"
ensure_label "ci"              "bfdadc" "GitHub Actions"
ensure_label "testing"         "0e8a16" "Test coverage"
ensure_label "tech-debt"       "fbca04" "Refactoring / cleanup"
ensure_label "ux"              "a2eeef" "User experience"
ensure_label "docs"            "0075ca" "Documentation"
ensure_label "web"             "1d76db" "Landing page"
ensure_label "enhancement"     "84b6eb" "New capability or improvement"
ensure_label "diagnostics"     "5319e7" "Option-click diagnostics view"
ensure_label "legal"           "553d66" "License / legal"
ensure_label "marketing"       "f9d0c4" "SEO / social / conversion"
ensure_label "revenue"         "006b75" "Monetization infrastructure"
ensure_label "performance"     "ededed" "Responsiveness"

echo "=== Ensuring milestones ==="
ensure_milestone "$M1" "Make the safety promise true: no termination or failure path leaves pmset modified without telling the user. Exit: kill-matrix test passes."
ensure_milestone "$M2" "Frictionless, trustworthy install: signed + notarized DMG, release automation, working install docs. Exit: clean Mac installs with zero Gatekeeper dialogs."
ensure_milestone "$M3" "Monetization: license decision, payments via merchant-of-record, trial + license keys, Sparkle updates, launch-ready landing page."

echo "=== Creating issues: P0 ==="

create_issue \
"BZ-001: Restore settings on all termination paths, not just the footer Quit button" \
"bug,safety" "$M1" \
"There is no \`applicationShouldTerminate\`/\`applicationWillTerminate\` in \`AppDelegate\` — the restore path only runs from the popover Quit button. Cmd+Q, logout, restart, Force Quit, \`kill\`, or a crash leave \`hibernatemode 25\` (and the other settings) applied system-wide. \`isActive\` persists in UserDefaults, so after reboot the UI shows \"on\" regardless of real pmset state.

**Fix:** implement \`applicationShouldTerminate\` (\`.terminateLater\` until restore completes), listen for \`NSWorkspace.willPowerOffNotification\`, and reconcile at launch: if a backup exists and \`isActive\` is false, offer to restore.

Files: \`Benzo/App/AppDelegate.swift\`, \`Benzo/ViewModels/BenzoViewModel.swift:117-122\`"

create_issue \
"BZ-002: PMSetState parser is fragile and can write a corrupt backup that breaks restore" \
"bug,safety" "$M1" \
"Parsing splits each line on the first **space** only, but \`pmset -g\` output contains tabs, multi-word keys (\"Sleep On Power Button\"), section headers, and annotated values (\"1 (sleep prevented by ...)\"). Garbage entries land in the backup JSON and are rejected by \`isValidPMSetParam\` at restore time — so deactivate/quit/revert fails exactly when the user needs it.

**Fix:** parse \`pmset -g custom\` (or only the \"Currently in use\" section), split on all whitespace, strip parenthetical annotations, and validate the backup at **save** time — fail activation loudly rather than persist garbage. Add fixture tests with real Intel + Apple Silicon output (BZ-020).

Files: \`Benzo/Models/PMSetState.swift:7-18\`, \`Benzo/Services/BackupService.swift:15-18\`"

create_issue \
"BZ-003: Deactivate with a missing/corrupt backup silently pretends success" \
"bug,safety" "$M1" \
"If \`BackupService.load()\` fails, \`deactivate()\` sets \`isActive = false\` and returns — the UI says Deep Sleep is off while pmset may still be in hibernatemode 25.

**Fix:** treat missing/corrupt backup as an error state: keep the toggle on, show an actionable message, and offer an explicit \"restore macOS defaults\" fallback (known-good defaults per key) requiring user confirmation.

Files: \`Benzo/ViewModels/BenzoViewModel.swift:272-278\`"

create_issue \
"BZ-004: quit() swallows restore failures with try?" \
"bug,safety" "$M1" \
"Both the backup load and the restore in \`quit()\` use \`try?\` — any failure is invisible and the app terminates leaving modified settings. This is the single most important error path in the product.

**Fix:** on failure, present a blocking alert (\"Couldn't restore your sleep settings — Retry / Quit Anyway\") and only terminate after success or explicit override. Log the failure (BZ-035).

Files: \`Benzo/ViewModels/BenzoViewModel.swift:117-122\`"

create_issue \
"BZ-005: Partial pmset apply with no rollback" \
"bug,safety" "$M1" \
"\`applySettings\` applies keys sequentially; a mid-loop failure leaves a mixed system state (some keys Benzo's values, some original) with no rollback and UI state that doesn't reflect reality.

**Fix:** snapshot state before applying; on failure, restore already-applied keys from the snapshot and surface a clear, distinct partial-failure error.

Files: \`Benzo/Services/PMSetService.swift:24-51\`"

create_issue \
"BZ-006: Notarization pipeline in build-dmg.sh is broken" \
"release-blocker,build" "$M2" \
"Combined defects make the credentialed path unusable: (1) on Developer ID export failure the script falls back to the **ad-hoc-signed** app but still submits it to notarization — Apple rejects it and \`set -euo pipefail\` kills the script before the DMG is created; (2) \`ExportOptions.plist\` lacks \`teamID\`/\`signingCertificate\`; (3) \`VERSION\` is unvalidated (empty → \`Benzo-.dmg\`); (4) \`notarytool submit\` on a bare .app, no JSON status parsing or log capture; (5) no \`codesign --verify\` gate.

**Fix:** notarize only when \`codesign -dv\` confirms a Developer ID signature, otherwise skip with a warning and still build the community DMG. Add teamID, fail fast on empty VERSION, zip before submit, verify signature, write \`build/SHA256SUMS\`, use an Applications-symlink DMG layout.

Files: \`scripts/build-dmg.sh\`. Depends on BZ-007."

create_issue \
"BZ-007: No hardened runtime or entitlements configured" \
"release-blocker,build" "$M2" \
"Only \`CODE_SIGN_STYLE = Automatic\` is set — no \`.entitlements\` file, no \`CODE_SIGN_ENTITLEMENTS\`, no \`ENABLE_HARDENED_RUNTIME\`. Notarization requires hardened runtime; this blocks BZ-006 end-to-end.

**Fix:** add a minimal entitlements plist, enable hardened runtime for Release, and confirm Process/osascript spawning still works under it.

Files: \`Benzo/Benzo.xcodeproj/project.pbxproj\`"

create_issue \
"BZ-008: No LICENSE file; license strategy undecided for monetization" \
"release-blocker,legal" "$M3" \
"README claims MIT but no \`LICENSE\` file exists — a legal ambiguity today and a strategic gate for revenue: MIT means anyone can redistribute builds for free, which constrains monetization to open-core/paid-convenience rather than a license-enforced paywall.

**Fix:** decide the model (roadmap recommendation: open-core — commit MIT, sell signed builds + auto-updates + support), then commit the license text. Decide before accepting outside contributions, while relicensing is still trivially possible.

Files: repository root, \`README.md:66-68\`. See \`02_roadmap-to-revenue.md\` §Milestone 3."

echo "=== Creating issues: P1 ==="

create_issue \
"BZ-009: isActive is never reconciled with real pmset state at launch" \
"bug,safety" "$M1" \
"\`isActive\` comes from UserDefaults; drift correction only runs on popover open, not at login-item startup. After a reboot, macOS update, or manual pmset change, the icon and the system disagree.

**Fix:** on launch (and wake notifications), read pmset, compare against expected state, reconcile or surface a warning.

Files: \`Benzo/ViewModels/BenzoViewModel.swift:36-67, 192-226\`"

create_issue \
"BZ-010: toggleSetting doesn't revert the checkbox when apply fails" \
"bug,ux" "$M1" \
"State mutates before the shell call; on failure an error shows but the checkbox stays flipped. The \`// Revert toggle\` comment at line 299 has no code under it.

**Fix:** revert \`settingStates[setting]\` in both catch branches (or apply-then-commit).

Files: \`Benzo/ViewModels/BenzoViewModel.swift:93-98, 291-303\`"

create_issue \
"BZ-011: All shell execution blocks the calling (main) thread" \
"bug,performance" "$M1" \
"\`Process.waitUntilExit()\` runs synchronously; activate/deactivate/toggle/setup all run on the main thread, freezing the popover for the duration of sudo+pmset — and the osascript path blocks the UI for as long as the password dialog is open.

**Fix:** move shell I/O to a background queue or actor, publish results on the main actor, disable controls while an operation is in flight.

Files: \`Benzo/Services/ShellExecutor.swift:90-115\` and all call sites in \`BenzoViewModel\`"

create_issue \
"BZ-012: Silent sudoers reinstall at launch triggers an unexplained admin prompt" \
"security,ux" "$M2" \
"If \`needsSudoersUpdate\`, init fires \`try? ShellExecutor.installSudoersRule()\` — an osascript **admin password dialog** with no user action and swallowed errors. Users should never see a privilege prompt they didn't initiate; it looks like malware.

**Fix:** show an in-popover banner (\"Benzo needs to update its permission rule\") that triggers the prompt on click.

Files: \`Benzo/ViewModels/BenzoViewModel.swift:62-66\`"

create_issue \
"BZ-013: Master toggle can be On while applying nothing" \
"bug,ux" "$M1" \
"With all checkboxes off, activation applies an empty list but still sets \`isActive = true\` — UI says \"Sedated\" while nothing changed; drift correction also no-ops.

**Fix:** require at least one enabled setting to activate (disable the toggle with a hint), or auto-enable Deep Sleep (hibernatemode).

Files: \`Benzo/ViewModels/BenzoViewModel.swift:252-263\`"

create_issue \
"BZ-014: Backup is only captured once, so re-activation can restore stale values" \
"bug,safety" "$M1" \
"Backup is written only when \`!hasBackup()\`. Deactivate → change pmset manually → re-activate: deactivating later restores the outdated snapshot.

**Fix:** refresh the backup on every activation from the *inactive* state (at that moment current pmset values are by definition the user's own).

Files: \`Benzo/ViewModels/BenzoViewModel.swift:254-258\`, \`Benzo/Services/BackupService.swift\`"

create_issue \
"BZ-015: Non-admin users pass setup but every pmset call fails" \
"bug,ux" "$M2" \
"The sudoers rule grants NOPASSWD to \`%admin\` only. A standard user's setup appears to complete (file exists ⇒ \`isSetupComplete\`), but \`sudo -n\` always fails with a cryptic error.

**Fix:** check group membership during setup and block with a clear \"Benzo requires an administrator account\" message.

Files: \`Benzo/Services/ShellExecutor.swift:82-84\`"

create_issue \
"BZ-016: Scheduled sleep timer survives deactivate/quit and re-activates the app" \
"bug,safety" "$M1" \
"\`cancelScheduledSleep()\` is not called from \`deactivate()\`/\`quit()\`. A user who sets a 30-minute timer and then turns Benzo off still gets their caffeinate processes killed and the Mac force-slept (via \`sleepNow()\`, which re-activates Benzo).

**Fix:** cancel the timer in deactivate and quit; also make the 0.5s \`sleepNow\` closure cancellable (BZ-023).

Files: \`Benzo/ViewModels/BenzoViewModel.swift:160-188, 272-289\`"

create_issue \
"BZ-017: README's Homebrew tap instructions point to a repo that doesn't exist" \
"release-blocker,docs" "$M2" \
"\`brew tap chrisrogers37/benzo\` → \`chrisrogers37/homebrew-benzo\` returns 404. The v0.3.0 release notes correctly use the direct raw-cask URL instead.

**Fix:** create the \`homebrew-benzo\` tap repo (cask contents already correct), or rewrite the README to the direct-cask install command until the tap exists.

Files: \`README.md:15-19\`, \`Casks/benzo.rb\`"

create_issue \
"BZ-018: No release automation (tag → DMG → GitHub release → cask bump)" \
"ci,release-blocker" "$M2" \
"Releases are fully manual: run \`build-dmg.sh\` locally, upload by hand, edit the cask sha256 by hand. Every manual step is drift risk (package.json already says 0.1.0).

**Fix:** \`release.yml\` on tag push using a macOS runner: build via \`build-dmg.sh\` (after BZ-006), attach DMG + SHA256SUMS, patch \`Casks/benzo.rb\`, populate notes from CHANGELOG. Signing/notarization secrets in Actions secrets.

Files: \`.github/workflows/\`"

create_issue \
"BZ-019: CI never compiles anything — broken Swift or JSX can merge to main" \
"ci" "$M2" \
"The only workflow runs \`npm audit\` + gitleaks.

**Fix:** add a landing-page job (\`npm ci && npm run build\`) and a macOS job (\`xcodebuild -project Benzo/Benzo.xcodeproj -scheme Benzo -configuration Debug build\`), both required on PRs.

Files: \`.github/workflows/security.yml\`"

create_issue \
"BZ-020: Zero tests; parsing and sudoers generation are untested" \
"tech-debt,testing" "$M1" \
"No test target exists. The highest-risk logic — \`PMSetState\` parsing, backup round-trip, \`buildSudoersRule()\`, wake-reason mapping, sleep-log pairing — is pure-ish logic that unit tests cover well.

**Fix:** add a macOS unit-test target, fixture tests using captured real \`pmset\` output, run in CI (BZ-019). Parser tests need no refactor and should land with BZ-002; service-level tests come after the DI refactor (BZ-037).

Files: project-wide"

create_issue \
"BZ-021: Social preview image 404s in production" \
"bug,marketing" "$M3" \
"\`og:image\`/\`twitter:image\` reference \`/og-image.png\`, which doesn't exist — every social share of the landing page shows a broken preview.

**Fix:** add a 1200×630 \`public/og-image.png\` and use absolute URLs.

Files: \`index.html:13,19\`, \`public/\`"

create_issue \
"BZ-022: pmset -a silently changes sleep behavior for every user on the Mac" \
"bug,docs" "$M2" \
"All writes are system-wide (\`-a\`); on shared Macs, one account activating Benzo alters hibernation for all accounts, and nothing in the UI or docs says so.

**Fix:** document prominently (README + first-run setup screen); optionally detect multiple local users and note it in the setup flow.

Files: \`Benzo/Services/PMSetService.swift\`"

echo "=== Creating issues: M3 deliverables (P2) ==="

create_issue \
"BZ-034: No uninstall story; sudoers rule lives forever" \
"enhancement,security" "$M3" \
"\`removeSudoersRule()\` exists but is never called; the cask's \`uninstall delete: \"/etc/sudoers.d/benzo\"\` can't remove a root-owned file. Paid apps get held to a higher standard — \"it left a sudoers file behind\" is a refund/1-star trigger.

**Fix:** add an \"Uninstall Benzo…\" action (restore settings → remove sudoers via admin prompt → offer to trash app); replace the cask stanza with a \`caveats\` block documenting manual cleanup.

Files: \`Benzo/Services/ShellExecutor.swift:69-73\`, \`Casks/benzo.rb:14-15\`"

create_issue \
"BZ-035: No structured logging or crash reporting" \
"enhancement" "$M3" \
"Restore failures, sudo errors, and parse failures are invisible for support — a brutal gap once there are paying users.

**Fix:** adopt \`os.Logger\` with subsystems (shell, backup, restore, diagnostics); consider opt-in crash reporting. No always-on telemetry (see roadmap \"What NOT to do\").

Files: project-wide"

create_issue \
"BZ-036: No auto-update mechanism (Sparkle)" \
"enhancement,revenue" "$M3" \
"No Sparkle/appcast; users must check GitHub releases manually, and stale installs keep old sudoers rules. Auto-update is also the delivery vehicle for the paid tier.

**Fix:** integrate Sparkle 2, generate the appcast in the release workflow (BZ-018), serve it from the landing page domain.

Files: project-wide. Depends on BZ-018."

echo "=== Creating umbrella issues (P2/P3 backlog) ==="

create_issue \
"Umbrella: Diagnostics correctness pass (BZ-024, BZ-029, BZ-030, BZ-032, BZ-050)" \
"bug,diagnostics" "" \
"Cluster of diagnostics-view defects, best fixed as one pass with shared log fixtures:

- **BZ-024** — settings verification shows green when inactive or when a disabled setting still holds Benzo's value (\`DiagnosticService.swift:132-150\`)
- **BZ-029** — \`pmset -g log\` parsing relies on locale/version-sensitive substrings; degrade gracefully and test against per-macOS-version fixtures (\`DiagnosticService.swift:22-74, 155-169\`)
- **BZ-030** — \`contains(\"User\")\` mislabels UserActivity wakes as \"Power Button\" (\`SleepSession.swift:38\`)
- **BZ-032** — USB panel queries only \`SPUSBDataType\`, empty on Apple Silicon (\`DiagnosticService.swift:78-91\`)
- **BZ-050** — diagnostics errors collapse to empty arrays with no user-visible cause (\`DiagnosticView.swift:180-181\`)"

create_issue \
"Umbrella: Sleep lifecycle & app behavior fixes (BZ-023, BZ-025 – BZ-028, BZ-031)" \
"bug,ux" "" \
"Smaller behavior defects (note BZ-023 pairs naturally with BZ-016 in Milestone 1):

- **BZ-023** — \`sleepNow\`'s 0.5s \`asyncAfter\` closure can fire after quit/deactivate; make it cancellable (\`BenzoViewModel.swift:141-149\`)
- **BZ-025** — disabling a setting whose keys are missing from backup silently keeps Benzo's values; warn or fall back to safe defaults (\`PMSetService.swift:40-50\`)
- **BZ-026** — timed sleep \`pkill caffeinate\` kills every caffeinate the user runs; kill only blocking PIDs from \`pmset -g assertions\` and show what will be killed (\`PMSetService.swift:80-84\`)
- **BZ-027** — launch-at-login toggle stays on when \`SMAppService.register()\` fails; re-read status in catch (\`BenzoViewModel.swift:313-325\`)
- **BZ-028** — global click monitor nil-return unchecked and leaks; implement \`popoverDidClose\` (\`AppDelegate.swift:113-115\`)
- **BZ-031** — Apple Silicon vs Intel \`hibernatemode 25\` / standby / autopoweroff differences unhandled; detect platform, document per-platform behavior (\`SleepSetting.swift:44-45\`)"

create_issue \
"Umbrella: Security hardening follow-ups (BZ-033, BZ-042)" \
"security,tech-debt" "" \
"- **BZ-033** — backup JSON has default permissions and no integrity check; any local process can rewrite it to push pmset to arbitrary numeric values on next restore. chmod 0600 + per-key range validation on load (\`BackupService.swift:15-24\`)
- **BZ-042** — security-audit Phase 02 never completed: \`.gitignore\` lacks \`.env*\` (notarization creds risk), Vite major upgrade undone (\`documentation/planning/security/full-audit_2026-03-21/02_env-hygiene-and-deps.md\`)"

create_issue \
"Umbrella: Landing page quality pass (BZ-038 – BZ-041, BZ-043, BZ-053, BZ-054)" \
"web,enhancement" "$M3" \
"Landing-page work needed before the marketing push:

- **BZ-041** — copy claims \"macOS Catalina and later\"; app requires Ventura 13+ (\`BenzoHybrid.jsx:1193-1195\`)
- **BZ-039** — no keyboard/AT accessibility: div-onClick controls, button-in-anchor CTA, no reduced-motion support
- **BZ-040** — SEO gaps: canonical/og:url, robots.txt, sitemap, JSON-LD \`SoftwareApplication\`
- **BZ-043** — mockup drift from native app: missing Launch-at-Login toggle, no SetupView, raw \`caffeinate\` blocker name, \`showOptions\` default, \`womp 0\` missing from pmset copy
- **BZ-038** — decompose the 1,370-line \`BenzoHybrid.jsx\` monolith (Mockup/, Marketing/, GatekeeperTray, shared theme + constants mirroring \`SleepSetting.swift\`)
- **BZ-053** — add \`vercel.json\` so deploy config is reproducible from the repo
- **BZ-054** — deep-link the DMG asset (after BZ-018), self-host fonts, retire \"isn't notarized\" copy once BZ-006/007 ship"

create_issue \
"Umbrella: Swift codebase debt burn-down (BZ-037, BZ-044 – BZ-049, BZ-051, BZ-052)" \
"tech-debt" "" \
"Refactoring and polish, incremental alongside feature work:

- **BZ-037** — \`BenzoViewModel\` god object + static service enums block testing; extract protocols (\`PMSetExecuting\`, \`BackupStoring\`), inject, split view model
- **BZ-044** — hardcoded \`v0.3.0\` in \`FooterView.swift:26\`; read \`CFBundleShortVersionString\`
- **BZ-045** — force unwraps/IUOs in \`AppDelegate\`, \`BackupService\`
- **BZ-046** — dead code: \`extractAssertionName\`, unused \`activeCount\`/\`isActive\`/\`capturedAt\` params
- **BZ-047** — misleading \`ShellError.userCancelled\` catches on paths that never prompt
- **BZ-048** — empty SwiftUI Settings scene (candidate home for the M3 license UI)
- **BZ-049** — menubar icon color duplicates \`BenzoTheme\` accent inline
- **BZ-051** — Info.plist duplication; \`CURRENT_PROJECT_VERSION\` frozen at 1
- **BZ-052** — package.json version drift (0.1.0 vs 0.3.0)"

echo ""
echo "=== Done ==="
if [ "$DRY_RUN" = "1" ]; then
    echo "Dry run — nothing was created. Re-run without DRY_RUN=1 to file."
else
    echo "Filed. Next steps (see 03_issue-filing-plan.md):"
    echo "  1. Add the 'filed as issues' header to ${TRACKER}"
    echo "  2. Update .claude/todo.md to reference issue numbers"
fi
