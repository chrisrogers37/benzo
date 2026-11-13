# Functional account-free packaging

Benzo’s account-free build includes the same functional power controls as an
optionally Developer ID-signed build. No Apple Developer membership, notarization,
custom signing role or background-service approval gates power access. Initial
**Set Up Power Access** requests one administrator approval for the Mac account
using Benzo. On, Off, quit and relaunch then reuse that finite grant.

The grant belongs to the account, so its other programs can invoke Benzo’s limited
commands. The installed command validates UID plus GeneratedUID, typed requests,
expected settings, durable revisions and execution evidence. It runs only when
requested and exits; no LaunchDaemon is bundled or registered. This architecture
supersedes the historical signed-daemon plan and its artifacts.

## Build and inspect without credentials

Use macOS with full Xcode and the Node version in `.nvmrc`. Follow the Debug,
Release and core-test commands in [README](../README.md#build-from-source), then:

```sh
# Choose a new absolute directory whose parent already exists.
./scripts/build-dmg.sh --mode development --output-dir /absolute/new/benzo-account-free
```

`development` remains the command-line compatibility name. The DMG contains
`Benzo Development.app`, an Applications shortcut and instructions identifying a
functional account-free, ad-hoc-signed, unnotarized build. This distinct filename
avoids replacing `Benzo.app` through an ordinary drag and drop. Both apps share the
production bundle identifier and recovery locations; do not run them together.

Packaging creates a universal archive, verifies exactly `Benzo` and `BenzoCommand`
in `Contents/MacOS`, rejects bundled daemons/XPC services and unexpected nested
code, signs each executable explicitly, checks each architecture and entitlements,
and verifies the DMG. It does not launch or install the app, install the command,
grant power access, change settings or publish a release. Output contains source
provenance, build settings, logs and `SHA256SUMS`. Never use an output directory
marked `INCOMPLETE` or an inspection marked `MOUNT_VALIDATION_INCOMPLETE`.

For a completed artifact, inspect it without launching the app:

```sh
bash scripts/tests/validate-development-dmg.sh /absolute/new/benzo-account-free
```

CI runs full-Xcode Debug/Release builds, unhosted XCTest for injected app and
command boundaries, a universal archive, web tests/build, packaging failure fixtures
and real DMG construction/read-only inspection. No CI check performs live setup,
`sudo`, `pmset`, app launch or privileged acceptance. Download artifacts before their
seven-day expiration and verify checksums/source provenance. Attempt-specific names
retain evidence from retries. These checks establish code and artifact evidence;
they do not complete the [native acceptance checklist](account-free-acceptance.md).

## Open a trusted unnotarized build

Download the exact artifact in a browser, retain its quarantine metadata, verify
its checksum and copy the app to Applications. If macOS blocks it, the owner may
choose **System Settings → Privacy & Security → Open Anyway**, then confirm Open
for that copy. This is an explicit per-app exception, not a background-service
approval. Never strip quarantine or globally disable Gatekeeper. See
[Apple’s guidance](https://support.apple.com/en-us/102445).

Initial setup installs `/Library/PrivilegedHelperTools/com.chrisrogers37.benzo-command`
and its exact rule at `/private/etc/sudoers.d/benzo-command`; root-owned account and
execution records live in `/private/var/db/com.benzo.command`. Ordinary app updates
retain the grant when the installed protocol is compatible. **Repair / Update Power
Access** is a separate administrator-approved action after resolving settings.
**Remove Power Access** revokes the exact rule and removes the command while keeping
account and recovery records. A failure must preserve evidence and remain actionable.

Historical flat backups, `/private/etc/sudoers.d/benzo`, and old daemon/root state
need restoration with the prior build or explicit administrator-assisted resolution.
The new build does not auto-erase or adopt them. Moving an app to Trash never proves
that settings were restored or a permission rule was retired.

## Optional Developer ID signing

A publisher who later chooses Apple Developer membership may use a valid Developer
ID Application certificate/private key to improve distribution trust:

```sh
./scripts/build-dmg.sh --mode developer-id \
  --output-dir /absolute/new/benzo-signed \
  --signing-identity CERTIFICATE_SHA1 --team-id TEAM_ID
```

Replace the placeholders with a 40-character hexadecimal certificate SHA1 and a
10-character team identifier. Keep certificates, private keys and passwords out
of the repository and logs. This mode checks the app/command identifiers, both
architectures, no unexpected entitlements, hardened runtime and secure timestamps.
It neither uploads nor notarizes nor publishes. Signing does not change the power
access contract or replace native acceptance.

## Optional notarization

Configure a notarytool Keychain profile interactively on the release machine.
Keep credentials in Keychain. Only an explicit upload request adds:

```sh
./scripts/build-dmg.sh --mode developer-id \
  --output-dir /absolute/new/benzo-notarized \
  --signing-identity CERTIFICATE_SHA1 --team-id TEAM_ID \
  --notarize --notary-profile benzo-notary
```

Require Apple’s Accepted response, inspect submission logs, validate app and DMG
staples and assess Gatekeeper. The script retains rejection/warning evidence and
never publishes. See [Apple’s notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).
This remains an optional distribution improvement, not a prerequisite for the
account-free app’s supported power controls.

## Delivery evidence and backup

Complete code, fixture and artifact checks before requesting user involvement in
the [single native checklist](account-free-acceptance.md). Record the exact tested
commit, version/build and checksums. Changes to the final artifact require relevant
rechecks. Publication and cask updates use the actually accepted artifact/checksum
and remain explicit delivery actions; Check for Updates never downloads or installs.

Before any planned factory reset, back up source, checksummed artifacts and acceptance
evidence to the owner’s chosen destination. A push does not back up local Documents
or signing keys. If signing credentials exist, export them securely through Keychain
and verify that separate backup. A factory reset remains an owner-controlled action.
