# Privacy and local data

Reviewed November 15, 2026 for the v0.4.0 account-free release. These notes describe
the command-based app and its local data. The earlier public v0.3.0 download uses
a different permission design. Native observations and remaining checks are
recorded in the [acceptance checklist](docs/account-free-acceptance.md).

The 0.5.0 development source adds an in-memory sleep countdown and an explicitly
approved finite sleep command. Countdown scheduling is not persisted. Dispatched
requests retain `sleep-intent.json`, its previous generation and durability markers
in the same private Benzo directory, plus typed receipts in the existing root
authority file. They contain operation/session IDs, boot identity, a short dispatch
expiry and completion evidence; they never store a password. The additional sleep
authority applies to programs in the setup account, just like settings access.
The v0.4.0 download does not include this feature.

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
  Explicit Set Up Power Access requests one administrator approval to install the
  app-bundled `BenzoCommand` at
  `/Library/PrivilegedHelperTools/com.chrisrogers37.benzo-command` and its exact,
  digest-pinned rule at `/private/etc/sudoers.d/benzo-command`. The grant binds the
  setup account's UID and GeneratedUID; other programs in that account can invoke
  the same finite commands. Root-owned `/private/var/db/com.benzo.command/`
  (0700, files 0600) retains account authority, request and boot identities,
  revisions, setting/precondition/target and execution evidence. It stores no
  administrator password or reusable authorization token. Apply and restore invoke
  the one-shot command through noninteractive `sudo`, changing exact selected
  profile/key values system-wide. No daemon or XPC service is installed. Ordinary
  operations do not request new administrator approval. Recovery reads use
  `pmset -g custom`; the command accepts no client-supplied paths.
- **Network:** the reviewed native source has no analytics, crash reporting or
  diagnostics upload implementation. Only an explicit Check for Updates requests
  the latest stable release metadata from GitHub's API for `chrisrogers37/benzo`.
  GitHub receives the ordinary connection data, including IP address and a fixed
  `Benzo-Update-Check` user agent; no recovery records, diagnostics, account identity
  or installed version are sent. Version comparison happens locally. The request
  uses an ephemeral session with cookies and persistent caching disabled; results
  are held in memory and cleared when the popover closes. View Release opens the
  fixed repository's validated release page in your browser, subject to the
  browser's own settings and GitHub's policies. There is no automatic polling,
  artifact download or installation. This says nothing about other software or
  macOS network activity.

Recovery evidence retains unresolved data, required previous generations and a
resolved receipt; it is not erased just because the app quits. Preferences and
legacy evidence have no automatic cleanup. Explicit Remove Power Access removes
only the recognized command rule and installed binary, retaining account and
recovery records. Removing the app does not restore settings, transfer account
ownership, erase command evidence or retire legacy permissions. Preserve recovery
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
