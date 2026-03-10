# Lessons

## pbxproj registration
New Swift files must be added to 4 sections in `project.pbxproj`: PBXBuildFile, PBXFileReference, PBXGroup, PBXSourcesBuildPhase. Missing any section causes "Cannot find X in scope" build errors.

## womp is not USB wake
`womp` is Wake-on-LAN (network wake). There is no pmset key for physical USB wake. Protection comes from `hibernatemode 25` cutting USB power after hibernation completes.

## App Store incompatibility
Benzo requires root access for pmset, which is incompatible with Mac App Store sandboxing. SMAppService privileged helper (XPC) cannot be used for App Store distribution when the helper needs root.

## Landing page mockup sync
Every native app UI change must be mirrored in `src/BenzoHybrid.jsx`. The mockup is interactive and must reflect current app state.

## import AppKit for NSApplication
`BenzoViewModel.swift` originally only imported Foundation and ServiceManagement. Adding `quit()` with `NSApplication.shared.terminate` requires `import AppKit`.
