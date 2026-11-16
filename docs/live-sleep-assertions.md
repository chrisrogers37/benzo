# Live sleep observations

Diagnostics includes a read-only **Keeping Your Mac Awake** section. It reads
`/usr/bin/pmset -g assertions` without elevation, with a three-second total budget
and a 256 KiB combined output limit. It has no connection to power authorization,
Sleep Now or timer admission, settings changes, process termination, telemetry,
or persistent process history.

Only an open Diagnostics panel polls. A read starts immediately and the next is
scheduled five seconds after completion. Manual refresh uses the same in-flight
slot. Navigation, popover close, system sleep and quit cancel ownership; reopening
waits for a canceled read to settle and rejects that visit's result. Deallocation
cancels outstanding tasks. If the runner cannot confirm its directly owned child
has stopped, refresh is paused for the entire app session, including after close
and reopen. The runner retains responsibility for its late cleanup.

Successful empty observations, initial loading, refreshing, read failure,
unsupported/malformed format, incomplete capture and stale observations are
separate states. A failed refresh keeps the last observation and its timestamp
visibly stale through retries until a fresh success. Closing discards process
observations; only unresolved read uncertainty survives within the app session.

The parser recognizes Apple's summary, owning-process and kernel sections. Missing
sections, inconsistent positive summary without owners and malformed candidates
fail instead of becoming empty. It uses the formatter's field encodings (UTF-8
process identity, MacRoman assertion names/details), not a lossy whole-output
fallback. Grouping is scoped to each observation and uses PID plus reported process
name, never friendly name. Duplicate assertion IDs must agree. An explicit
suspension excludes a row from active groups; a timeout marker alone does not,
since TimeoutActionLog can leave an assertion active.

Automatic idle-sleep, system-sleep, display/other activity, and system/kernel
information have distinct presentation. Idle prevention does not guarantee that
an explicit Sleep Now request is blocked. Neither a connected USB device nor
unclassified activity is labeled a sleep blocker. Assertion details remain
available as secondary disclosure content.

The active website demo uses fictional, injected observations and the same visible
states/lifecycle. It cannot inspect the visitor's Mac. Historical unbundled
mockups remain unchanged.

## Validation boundaries

Parser/service and refresh tests use independent synthetic datasets and injected
read/clock/wait boundaries. They never call live diagnostic or power adapters.
Web tests exercise classification, empty/error/stale states, no overlap, cancellation,
late results, navigation, close/reopen, quit, hidden pages and unmounting.

Local Command Line Tools typechecking is not a full Xcode or XCTest pass. Required
CI supplies Debug/Release builds, the unhosted core tests, packaging checks,
web tests/build, dependency audit and Gitleaks. Native visual layout, keyboard and
VoiceOver behavior, lifecycle in the installed application, and physical sleep
acceptance remain separate checks. This feature does not authorize installation,
launch/quit of the owner's app, changes to host settings or a native release.

Parser references:
- https://github.com/apple-oss-distributions/PowerManagement/blob/main/pmset/pmset.m
- https://github.com/apple-oss-distributions/IOKitUser/blob/main/pwr_mgt.subproj/IOPMLib.h
