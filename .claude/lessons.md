# Lessons

## Paid enrollment is a distribution boundary, not a development stop
The owner wants all pre-enrollment engineering completed before paying for Apple
Developer membership. Explain when our own helper identity policy requires a
Developer ID build even for live testing. Keep source integration, fake-based
tests, UI work and development packaging moving without credentials. Never call
those checks signed permission acceptance, or weaken the helper to bypass it.

## Let the popover own its window geometry
The old native app consumed a CPU core in a frame-change observer that queried
SwiftUI fitting size and then resized the popover's window. Use the public hosting
controller preferred-content sizing behavior with bounded SwiftUI content;
never feed window frame notifications back into window resizing. A displayed,
synthetic popover verified growth, height capping and shrinking without that loop.
An offscreen controller alone did not prove presentation behavior.

## pbxproj registration
New Swift files must be added to 4 sections in `project.pbxproj`: PBXBuildFile, PBXFileReference, PBXGroup, PBXSourcesBuildPhase. Missing any section causes "Cannot find X in scope" build errors.

## womp is not USB wake
`womp` is Wake-on-LAN (network wake). Do not infer physical USB power behavior
from `hibernatemode 25` or any settings readback; that requires separate hardware
evidence. Current Benzo only applies and restores reported settings.

## App Store incompatibility
Benzo requires root access for pmset, which is incompatible with Mac App Store sandboxing. SMAppService privileged helper (XPC) cannot be used for App Store distribution when the helper needs root.

## Landing page mockup sync
Mirror native UI changes in the active `src/landing/NativeAppDemo.jsx`,
`src/demo/useBenzoDemo.js` and `src/design/appPresentation.js`. Preserve unbundled
historical mockups; they do not define current product behavior.

## import AppKit for NSApplication
`BenzoViewModel.swift` originally only imported Foundation and ServiceManagement. Adding `quit()` with `NSApplication.shared.terminate` requires `import AppKit`.

## Hidden modifier gestures need a visible affordance
The original timed-sleep UX gated the picker behind ⌘-click on the Sleep Now button with no tooltip, hint text, or CHANGELOG entry. Users could not find it (and could not even remember which modifier was used). Rule: when a feature lives inside a popover/menubar surface, expose it with a visible control (split button, chevron, clock icon, etc.) rather than a modifier-click. Reserve modifier-click for power-user shortcuts, not for the only path to a feature.
