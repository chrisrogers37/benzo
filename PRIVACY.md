# Privacy and local data

Reviewed November 4, 2026. Native behavior below describes
[recovery source revision c291011](https://github.com/chrisrogers37/benzo/tree/c2910116eaaa0d8019572c6768a8b226bbe07d33/Benzo/Benzo),
not verified behavior of the older v0.3.0 download. Update-checker behavior is
outside this revision and must be documented when delivered.

## Mac app

- **Preferences:** selected options persist in macOS user defaults. Control state
  is derived from recovery evidence and current reads; an old saved active flag
  is only legacy evidence. Launch at Login uses macOS's login-item service when selected.
- **Recovery evidence:** `~/Library/Application Support/Benzo/` stores captured
  originals per reported power profile, frozen selections, timestamps, observed
  values, operation steps and results in `recovery-journal.json`. Previous
  generations, `recovery-receipt.json`, execution fences/markers and a stable lock
  support recovery and cooperating-instance exclusion. Evidence includes the
  account UID, host UUID, boot identity and generated session/operation IDs; these
  stay local. The directory is private (0700) and evidence files are 0600. The
  legacy `original-pmset.json`, if present, is preserved without treating its flat
  values as verified per-profile originals.
- **Diagnostics:** local reads of `pmset -g`, `pmset -g log` and
  `system_profiler SPUSBDataType -json` provide settings, sleep/wake records,
  battery readings, wake reasons and USB device information. Benzo holds parsed
  display results in memory; this source does not write diagnostic log files.
  macOS manages its own system logs separately.
- **Permissions and writes:** the source observes metadata at
  `/private/etc/sudoers.d/benzo`; presence does not establish authorization.
  Applying/restoring settings writes exact selected profile/key values system-wide
  through macOS administrator prompts. Recovery reads use `pmset -g custom`.
  Benzo does not save the administrator password or create a standing grant.
- **Network:** the reviewed native source has no analytics, crash reporting or
  diagnostics upload implementation. This says nothing about other software or
  macOS network activity.

Recovery evidence retains unresolved data, required previous generations and a
resolved receipt; it is not erased just because the app quits. Preferences and
legacy evidence have no automatic cleanup in this source. App
removal does not restore settings or retire legacy permissions. Preserve recovery
evidence if the outcome is uncertain; see [recovery and removal](README.md#recovery-and-removal).

## Security reports

Report vulnerabilities privately through the [security policy](SECURITY.md). Do not
include private backups, full system logs, or secrets in a report.

## Website and external services

The browser demo uses fictional readings and in-memory state. It cannot read your
Mac's diagnostics or change its settings. The active site code contains no
analytics or tracking scripts and does not persist demo state in browser storage.

Vercel hosts the website and receives ordinary web requests. Hosting logs and
retention are separate from the app's local data; this source review does not
verify those settings. Following GitHub, Apple or email links involves those
services and their data handling. GitHub issues are public: share only necessary,
redacted details, never private backups or full system logs. Email is handled by
the sender's provider and the recipient.
