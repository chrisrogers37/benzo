# Lasting permission amendment — November 13, 2026

The owner approved replacing repeated AppleScript elevation with an app-bundled,
signed and notarized SMAppService LaunchDaemon and guided setup. The authorized
account is **the local account completing setup** (artemis on the current test
Mac), not every user or every administrator. Do not hardcode this account name.
Apple Developer enrollment is deferred while source implementation proceeds;
Developer ID signing and native permission acceptance remain release gates.

**November 13 clarification:** complete all engineering, integration and
development packaging before paid enrollment. The current account policy and
Developer ID trust boundary remain unchanged. The owner authorized integration
of the already implemented packaging, updater and accessibility work in this
recovery branch; do not wait for signed acceptance to do that independent work.
See [release preparation](../../../../docs/release-preparation.md). Signed testing,
notarization and public release are still pending and distinct from development
packaging. No credentials are needed to build or test the development artifact.

## Scope and authority

Continue in the existing recovery worktree/PR #104. Preserve the primary checkout
and the separate packaging, update-checker and accessibility work. The old
persistent-AppleScript prototype was archived outside the repository and removed;
the implementation baseline is clean commit c858eb1. Its read-only experiments
are historical evidence, not helper acceptance.

The owner intends to factory reset this Mac after Benzo works. Before that reset,
verify remote source commits, published release assets and a portable handoff.
Signing private keys, passwords and authorization tokens do not belong in that
handoff or repository. A factory reset is a separate task, not authorized here.
Existing scoped apply/restore acceptance does not authorize unattended helper
installation, permission changes, sleep/reboot or unrelated fleet changes.

## Security contract

- The unprivileged menu app registers the bundled service only after an explicit
  setup action. Explain macOS approval and open the supported System Settings
  page. Launch at Login is separate.
- The daemon accepts only the exact signed Benzo client identity and intended
  Apple-issued signing team. The app authenticates the exact helper identity.
  Ad-hoc or missing identities fail closed; never add an accept-all debug path.
- Service approval is not account enrollment. Enrollment requires an explicit
  administrator-authorized setup exchange. Bind the owner to authenticated
  connection credentials, never a client-supplied user name or UID. Persist that
  ownership in checked root-owned storage; do not transfer it on disconnect,
  logout, reinstall, missing files or a timeout. Account replacement must not
  inherit permission solely by reusing a numeric UID.
- Normal setting operations use the enrolled account's authority and require no
  new interactive authorization. Denial, revocation, unavailable/incompatible
  helper and a different account are visible states. "Enabled" alone is not
  proof the helper can serve a compatible authenticated request.
- Expose a bounded vocabulary for supported profiles, keys and values. No shell,
  arbitrary path/command, client journal read, sleep or reboot endpoint.
- Preserve capture, immutable originals, frozen selection, durable intent,
  execution fences, readback, conflict handling and truthful quit behavior.
  Lost replies are uncertain execution, never automatic retry or rollback.
- The helper serializes writes and retains durable machine-wide admission and
  uncertain execution evidence. A disconnected GUI cannot release this state.
- Upgrade/removal must stop admission, preserve unresolved evidence and use the
  supported asynchronous service lifecycle. Removing permission never implies
  that settings were restored.

## Delivery sequence

1. Implement and review the shared protocol, account enrollment policy, signed
   identity/status exchange, bundled daemon target and setup states using fakes.
2. Connect only the existing bounded setting operations after reviewing the
   admission and execution contract against recovery behavior.
3. Run unhosted tests, web parity tests, Debug/Release builds and security CI.
   Only Command Line Tools are installed locally; swiftc checks are not XCTest.
4. With a Developer ID identity available, build/notarize a reviewable artifact.
   Obtain approval for its concrete host installation/registration, then test
   initial approval, denial, another account/client, revocation, relaunch,
   apply/restore/quit, lost replies and lifecycle behavior. No release before
   those checks and the remaining integration/accessibility gates pass.
5. Publish the accepted artifact and verify portable handoff before any reset.

## Sources

- [Apple DTS: privilege escalation](https://developer.apple.com/forums/thread/708765)
- [SMAppService setup](https://developer.apple.com/forums/thread/802443)
- [Helper approval status](https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos)
- [Secure helper design](https://developer.apple.com/library/archive/documentation/Security/Conceptual/SecureCodingGuide/DesigningSecureHelpers/DesigningSecureHelpers.html)
- [XPC code requirements](https://developer.apple.com/forums/thread/681053)
- [Developer ID](https://developer.apple.com/developer-id/)

Implementation and acceptance receipts will be appended here. This amendment
does not claim that a helper is installed, permissions are granted, or a native
release has been published.

## Source review checkpoint

Implemented the app-bundled daemon, explicit setup/account enrollment, direct
allowlisted pmset execution, UID plus local GeneratedUID owner binding, root-owned
revision/fence storage, and active browser parity. The existing GUI recovery
journal remains the owner of captured originals and conflict decisions.

Independent review found and corrected duplicate no-execution classification,
account identity revalidation after asynchronous capture, reply revision checks,
extended ACL protection, stale helper detection and explicit quiescent replacement.
The helper reports a startup code hash validated against its running code; the app
compares it with the signed embedded helper. Replacement requires the account's
lifetime recovery lock, resolved settings and no setup/write overlap. The helper's
replacement pause is process-local: it coordinates the supported signed app,
not an independently modified signed client that bypasses the GUI contract.

The root evidence retains one earlier-boot uncertain request. A second unresolved
request cannot discard that record: it requires administrator-assisted recovery.
There is no automatic account transfer, journal deletion, sleep command or retry.

Native/helper source typechecks with the installed Command Line Tools. Fake-only
policy and nonroot filesystem scenario bodies also ran in temporary assertion
harnesses; those are not XCTest. Full Xcode Debug/Release, unhosted XCTest and
security checks are required on the pushed commit. Browser setup was exercised
through first launch, macOS approval simulation, separate account authorization,
and ready state; no real Mac permission was requested by the browser demo.

Signed XPC identity rejection, installation/approval, live account enrollment,
revocation, reboot persistence, helper replacement/removal and exact selected-value
apply/restore/quit remain native acceptance gates. The known contrast defects are
owned by PR #105 and must be integrated before release. Packaging #102 and manual
update checker #103 are still separate integration work. No helper was installed
or registered during source development.
