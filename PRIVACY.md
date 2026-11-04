# Privacy and local data

Reviewed November 4, 2026. Native behavior below describes
[source revision c3a9070](https://github.com/chrisrogers37/benzo/tree/c3a9070b16c602c48b833a6e338fb40930ae4b04/Benzo/Benzo),
not verified behavior of the older v0.3.0 download. Update-checker behavior is
outside this revision and must be documented when delivered.

## Mac app

- **Preferences:** active state and selected options persist in macOS user
  defaults. Launch at Login uses macOS's login-item service when selected.
- **Saved originals:** on first activation without an existing backup, Benzo saves
  parsed `pmset` settings and a capture timestamp in
  `~/Library/Application Support/Benzo/original-pmset.json`.
- **Diagnostics:** local reads of `pmset -g`, `pmset -g log` and
  `system_profiler SPUSBDataType -json` provide settings, sleep/wake records,
  battery readings, wake reasons and USB device information. Benzo holds parsed
  display results in memory; this source does not write diagnostic log files.
  macOS manages its own system logs separately.
- **Permissions and writes:** the source observes metadata at
  `/private/etc/sudoers.d/benzo`; presence does not establish authorization.
  Applying/restoring settings writes system-wide values across power sources.
- **Network:** the reviewed native source has no analytics, crash reporting or
  diagnostics upload implementation. This says nothing about other software or
  macOS network activity.

Saved originals and preferences have no automatic cleanup in this source. App
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
