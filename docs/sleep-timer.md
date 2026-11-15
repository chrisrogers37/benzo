# Sleep Now and timer follow-up

This is the separate 0.5.0 development follow-up requested after v0.4.0 was
published. The downloadable v0.4.0 still has Sleep Now disabled. This document
amends the earlier timer-removal scope only for the bounded behavior below.

## Behavior

Apply the selected settings first. With a verified active session and compatible
power access, Sleep Now sends one sleep request. The clock button offers 5, 15,
30 and 60 minutes; choosing a preset starts a countdown. Clicking the countdown
cancels it. Closing the panel retains it; Off, quit, setup, recovery, lost
eligibility and system sleep/wake cancel it. Restarting never rearms a timer,
and waking never fires an overdue countdown.

Sleep does not apply settings automatically, change captured originals, kill
sleep blockers or promise hibernation/USB power behavior. Off and Quit retain
their existing restore behavior. A successful command means a request was sent;
it does not establish physical sleep. Once dispatched, a request is pending until
its result is reconciled; cancellation does not recall a sent request.

## Permission compatibility

The new app continues to use a compatible 0.4.0 tool for settings. Only sleep is
disabled when that tool lacks the advertised capability. From resolved Off,
Manage Power Access → Advanced → Repair / Update Power Access requests one
administrator approval for the added account-level sleep authority. Other programs
in that account can invoke the finite sleep command. There is no developer-account
gate, daemon or administrator prompt for ordinary sleep actions after setup.

The installer recognizes exact old and new digest-bound policies, including during
rollback. It does not accept a wildcard or foreign rule. Account ownership,
grant epoch, watermark and recovery records survive the explicit update.

## Execution and recovery

Immediate sleep and timer expiry share one serialized coordinator admission.
They recheck session identity and eligibility after asynchronous work. A short
continuous-clock expiry bounds delayed command delivery. The root tool receives
only a typed identity/expiry request and executes fixed `pmset sleepnow`; it has
no scheduler or user-supplied arguments.

Sleep uses the existing root lock, epoch, sequence and one pending-operation slot.
Settings requests keep their existing representation. Typed sleep evidence uses
schema 2 so older tools and clients reject outstanding sleep work. A terminal
acknowledgement returns the authority file to schema 1 without resetting the
watermark. Status, no-spawn sealing and acknowledgement remain possible after a
request expires; duplicate or retired requests never execute again.

The account-local sleep intent is separate from the successful apply operation
and is protected by the same account lock and durability checks. Its terminal
result is persisted before acknowledging the root receipt. Proved child termination
with an unknown sleep outcome is terminal evidence; unproved child lifetime stays
fenced. A wake notification alone cannot clear that fence or establish success.

## Verification

Injected tests cover countdown cancellation and stale callbacks, eligibility and
quit races, short-expiry rejection, durable intent/result/ACK failures, duplicate
requests, old-tool compatibility and exact-policy upgrade/rollback. Web interaction
tests cover the corresponding controls. Full Xcode builds, XCTest and packaging
remain separate from supplemental Command Line Tools checks.

After source review and CI, owner-involved acceptance should use the exact built
artifact on a Mac that may safely sleep: update power access from resolved Off,
apply a supported setting, request sleep and wake, confirm Off restores originals,
then exercise a preset and cancellation. Observe prompt counts and native keyboard/
VoiceOver behavior. Do not run those privileged or physical-sleep checks on the
always-on Mac while the owner is AFK. No such result is claimed by this document.
