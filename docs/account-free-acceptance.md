# Account-free native acceptance

Run this checklist on an explicitly approved test Mac after source tests and DMG
inspection are complete. It collects the remaining user-involved checks in one
place. Passing CI or signing verification does not check any box below. No Apple
Developer account is required. Physical sleep, hibernation, USB power behavior and
battery savings are outside these checks. The v0.4.0 release is authorized with
Sleep Now and its timer disabled. No sleep/reboot or further privileged acceptance
is authorized while the owner is AFK.

## Recorded observations

On November 15, 2026, the owner exercised source
`09ce88f285dd73138763a7e5f35b5a0c80f1a392`, version **0.3.0 build 1**, on an
Apple silicon Mac Mini (`Mac16,10`), macOS **26.1 (25B78)**. This was the
account-free development artifact, distinct from the older public v0.3.0 release.
Its DMG SHA256 was
`89ca02e437b2e4859437a951e0347e3fde9e740017a3fbfad0b87b34632506f4`.

| Case | Observed result |
| --- | --- |
| Download and launch | Baseline evidence recorded a browser download with quarantine intact; later checks found the app running from Applications. The precise Gatekeeper interaction was not recorded. |
| Initial setup | The owner reported one setup approval. A noninteractive `version-v1` command returned the bound account identity successfully. |
| Apply | Disable Network Wake changed the reported AC `womp` value from 1 to 0; the journal recorded the original and successful readback. |
| Off | All reported settings matched the full baseline; the journal was resolved and its receipt matched. The owner reported no administrator prompt. |
| Second On → Quit | All reported settings again matched the full baseline, the journal and receipt agreed, execution sequence 4 was acknowledged and completed, and no Benzo process remained. The owner reported no administrator prompt. |
| Relaunch | The app ran from Applications, the full baseline still matched, and the owner reported Off with no new prompt. |

The evidence is retained locally in the
`benzo-account-free-acceptance-20261115-002657/` bundle:
`00-baseline.json`, `04-applied-system-check.json`, `05-off-system-check.json`,
`06-quit-system-check.json` and `07-relaunch-check.json`. Keep the original bundle
local; redact account and machine identifiers before sharing its contents.

These observations do **not** cover the final v0.4.0 build 2 UI/package. Native
other-account/UID-reuse checks, cancellation and failure paths, missing-tool
recovery, repair/removal/reinstall, compatible upgrades, legacy combined flows
and VoiceOver remain untested. Physical sleep was not exercised. The complete
checklist below remains open; source and CI tests do not fill those gaps.

## Checklist for an exact artifact

Record the source commit, version/build, app and DMG SHA256, macOS version, hardware,
account name/UID/GeneratedUID, chosen settings, initial profile values and outcome
for each case. Record prompt counts and what each prompt approved; distinguish
macOS’s initial per-app opening decision from Benzo’s power-access setup grant.
Preserve recovery evidence and stop privileged changes if a case becomes uncertain.

- [ ] **Existing installation.** If another Benzo is running, use that build to
  restore its captured settings, verify Settings Are Off, then quit before
  replacing the app. Keep its recovery records; do not remove evidence to get
  past a setup or recovery warning.
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
- [ ] **Removal and reinstall.** From resolved Off, open Manage Power Access,
  expand Advanced and confirm Remove Power Access.
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
