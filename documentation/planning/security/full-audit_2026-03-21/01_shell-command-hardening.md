# Phase 01: Shell Command Hardening

**Status:** ✅ COMPLETE
**Started:** 2026-03-21
**Completed:** 2026-03-21
**PR title:** `security: validate pmset values before shell interpolation`
**Severity:** MEDIUM
**Effort:** Small (< 1 hour)
**Findings addressed:** #1 (command injection defense-in-depth)

---

## Files Modified

- `Benzo/Benzo/Services/PMSetService.swift`
- `Benzo/Benzo/Services/ShellExecutor.swift`
- `Benzo/Benzo/Services/BackupService.swift` (optional — validation could live here instead)

---

## Dependencies

None — this phase can be implemented independently.

---

## Detailed Implementation Plan

### Finding #1: Input validation for shell-interpolated values

**Problem:** `PMSetService.restoreValues()` (line 59-60) reads key-value pairs from `~/Library/Application Support/Benzo/original-pmset.json` and interpolates them directly into shell commands:

```swift
// Current code (PMSetService.swift:59-60)
for (key, value) in backup.values where relevantKeys.contains(key) {
    commands.append("/usr/bin/pmset -a \(key) \(value)")
}
```

If the JSON file were tampered with (e.g., a value of `0; rm -rf /`), the interpolated string becomes `sudo /usr/bin/pmset -a hibernatemode 0; rm -rf /`. The same pattern exists in `applySettingsWithRestore()` (line 37-38).

**Note:** The hardcoded enum values in `SleepSetting.pmsetCommands` are safe — they never touch user/file input. Only the backup restore path is vulnerable.

**Fix:** Add a validation function that ensures pmset keys and values match expected patterns before interpolation.

```swift
// Add to PMSetService.swift

/// Validate that a pmset key and value are safe for shell interpolation.
/// Keys must be alphabetic. Values must be numeric digits only.
private static func isValidPMSetParam(_ key: String, _ value: String) -> Bool {
    let letters = CharacterSet.letters
    let digits = CharacterSet.decimalDigits
    return !key.isEmpty && key.unicodeScalars.allSatisfy(letters.contains)
        && !value.isEmpty && value.unicodeScalars.allSatisfy(digits.contains)
}
```

Then guard every backup-value interpolation:

In both `restoreValues()` and `applySettingsWithRestore()`, validate backup values before interpolation. If any value fails validation, throw an error so the user knows the restore was aborted (not partially applied):

```swift
// PMSetService.swift:restoreValues() — AFTER
for (key, value) in backup.values where relevantKeys.contains(key) {
    guard isValidPMSetParam(key, value) else {
        throw PMSetError.invalidBackupData(key: key)
    }
    commands.append("/usr/bin/pmset -a \(key) \(value)")
}
```

```swift
// PMSetService.swift:applySettingsWithRestore() — AFTER
if let originalValue = backup.values[key] {
    guard isValidPMSetParam(key, originalValue) else {
        throw PMSetError.invalidBackupData(key: key)
    }
    commands.append("/usr/bin/pmset -a \(key) \(originalValue)")
}
```

Add error type to PMSetService:

```swift
enum PMSetError: LocalizedError {
    case invalidBackupData(key: String)

    var errorDescription: String? {
        switch self {
        case .invalidBackupData(let key):
            return "Backup data for '\(key)' is invalid. Delete ~/Library/Application Support/Benzo/original-pmset.json and re-activate."
        }
    }
}
```

### Finding #2: Sudoers scope — DROPPED

Dropped from this PR. The sudoers rule's blast radius is limited to power management settings. Input validation from Finding #1 is the higher-value fix.

---

## Verification Checklist

- [ ] Add a unit test or assertion that `isValidPMSetParam("hibernatemode", "25")` returns true
- [ ] Verify `isValidPMSetParam("hibernatemode", "0; rm -rf /")` returns false
- [ ] Verify `isValidPMSetParam("key$(whoami)", "1")` returns false
- [ ] Build the app: `xcodebuild -project Benzo/Benzo.xcodeproj -scheme Benzo -configuration Debug build`
- [ ] Activate Benzo, toggle settings, deactivate — verify restore works correctly
- [ ] Manually inspect `~/Library/Application Support/Benzo/original-pmset.json` to confirm values are numeric

---

## What NOT To Do

- **Don't use an allowlist of specific pmset keys** — this couples the validation to the enum and breaks if new settings are added. Pattern-based validation (alphanumeric key, numeric value) is more robust.
- **Don't switch to `Process.arguments` array** to avoid shell injection — the code uses `/bin/sh -c` intentionally to chain multiple `sudo` commands with `&&`. Refactoring to individual `Process` calls per command would work but is a larger change than needed. Input validation achieves the same defense.
- **Don't log rejected values** — they could contain malicious content that ends up in system logs.
- **Don't silently skip invalid entries** — throw an error so the user knows the backup is corrupt. A partial restore is worse than no restore.
