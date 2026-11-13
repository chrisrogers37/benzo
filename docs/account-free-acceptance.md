# Account-free native acceptance

Run this checklist on an explicitly approved test Mac after source tests and DMG
inspection are complete. It collects the remaining user-involved checks in one
place. Passing CI or signing verification does not check any box below. No Apple
Developer account is required. Physical sleep, hibernation, USB power behavior and
battery savings are outside these checks.

Record the source commit, version/build, app and DMG SHA256, macOS version, hardware,
account name/UID/GeneratedUID, chosen settings, initial profile values and outcome
for each case. Record prompt counts and what each prompt approved; distinguish
macOS’s initial per-app opening decision from Benzo’s power-access setup grant.
Preserve recovery evidence and stop privileged changes if a case becomes uncertain.

- [ ] **Downloaded artifact and opening.** Browser-download the exact DMG with
  quarantine intact; verify `SHA256SUMS`, mount and copy the app to Applications.
  Observe normal Gatekeeper handling. If the owner trusts this unnotarized copy,
  use its per-app Open Anyway option and confirm Open. Do not strip quarantine or
  disable Gatekeeper. Record any macOS policy restriction that prevents this.
- [ ] **One named-account setup.** With no unresolved legacy/session evidence,
  launch from Applications. Confirm startup, diagnostics and Check Again request
  no elevation. Choose Set Up Power Access once. The administrator prompt must
  identify the account receiving the finite grant and disclose Mac-wide power
  effects. Confirm one Benzo setup prompt, readiness only after verification, the
  exact installed command/rule, and no daemon/background-service registration.
  A different account must not gain access; recreated/reused UID must not inherit
  the original GeneratedUID-bound grant. The grant intentionally covers programs
  in the setup account, not only this app.
- [ ] **On → Off → On → Quit → relaunch.** Capture the full baseline; select only
  reported supported settings. Check each apply readback and exact captured-value
  restoration. Count no further administrator prompts across On, Off, second On,
  restore-on-Quit and relaunch. A successful readback is configuration evidence only.
- [ ] **Cancellation, denial and failures.** Cancel or deny initial setup on a
  clean test account and verify actionable feedback with controls disabled and
  evidence preserved. Exercise approved read/write/lost-reply failure cases with
  injected fixtures first; native failure testing must not introduce uncontrolled
  commands. Verify Retry/Stay Open/Quit Anyway, preserved originals/fences and no
  automatic replay or surprise elevation after a failed operation.
- [ ] **Revocation and missing tool.** From resolved Off, revoke access using the
  explicit removal flow and confirm later controls cannot write or automatically
  request approval. In an approved controlled missing/changed-tool case, retain
  records and verify actionable failure. If restoration becomes blocked, preserve
  the app/state and use administrator-assisted recovery; do not erase evidence.
- [ ] **Compatible app upgrade and explicit tool update.** Restore to Off and
  replace only the app with a compatible-protocol build. Relaunch, On, Off and Quit
  must reuse the existing grant without a new setup prompt. A tool update must use
  explicit Repair / Update Power Access with one approval. Active sessions or
  unresolved execution must block repair/removal. Failed update preserves owner
  and recovery records and must not silently grant another account access.
- [ ] **Removal and reinstall.** From resolved Off, confirm Remove Power Access.
  Verify only the exact recognized command rule and installed binary are removed;
  account/recovery records stay. Quit and remove the app. Reinstall, explicitly
  set up again and verify the original owner remains bound. A cancelled/failed
  removal must preserve usable recovery evidence and report the actual result.
- [ ] **Legacy and combined UI.** Where historical flat backups, old sudoers rules
  or daemon state exist, confirm they block unsafe adoption and are not erased.
  Restore with the prior build or arrange explicit manual resolution. Check the
  installed app with keyboard, spoken VoiceOver, menu entry/return, Reduce Motion,
  larger text/display and constrained placement. Check manual update navigation,
  stale-result clearing and recovery/setup interaction.

Mark each result observed, failed, or not run with evidence. Do not mark the whole
checklist accepted while any required case is unresolved. Source completion,
artifact creation, native acceptance and public release are separate outcomes.
