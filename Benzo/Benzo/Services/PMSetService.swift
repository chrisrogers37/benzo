import Foundation

enum PMSetError: LocalizedError {
    case invalidBackupData(key: String)

    var errorDescription: String? {
        switch self {
        case .invalidBackupData(let key):
            return "Backup data for '\(key)' is invalid. Delete ~/Library/Application Support/Benzo/original-pmset.json and re-activate."
        }
    }
}

enum PMSetService {
    private static let pmsetPath = "/usr/bin/pmset"

    /// Read current pmset values
    static func readCurrentState() throws -> PMSetState {
        let output = try ShellExecutor.runDirect(pmsetPath, ["-g"])
        return PMSetState(parsing: output)
    }

    /// Apply enabled settings. First failure aborts the rest.
    static func applySettings(_ enabledSettings: [SleepSetting]) throws {
        for setting in enabledSettings {
            for (key, value) in setting.pmsetCommands {
                try ShellExecutor.runDirectWithSudo(pmsetPath, ["-a", key, value])
            }
        }
    }

    /// Apply enabled settings and restore original values for disabled ones
    static func applySettingsWithRestore(_ enabledSettings: [SleepSetting], disabledSettings: [SleepSetting], backup: OriginalSettingsBackup?) throws {
        for setting in enabledSettings {
            for (key, value) in setting.pmsetCommands {
                try ShellExecutor.runDirectWithSudo(pmsetPath, ["-a", key, value])
            }
        }

        if let backup = backup {
            for setting in disabledSettings {
                for key in setting.pmsetKeys {
                    if let originalValue = backup.values[key] {
                        guard isValidPMSetParam(key, originalValue) else {
                            throw PMSetError.invalidBackupData(key: key)
                        }
                        try ShellExecutor.runDirectWithSudo(pmsetPath, ["-a", key, originalValue])
                    }
                }
            }
        }
    }

    /// Defense-in-depth: backup data is user-influenced via the JSON file on disk,
    /// so still validate format even though argv exec defangs shell injection.
    private static func isValidPMSetParam(_ key: String, _ value: String) -> Bool {
        let letters = CharacterSet.letters
        let digits = CharacterSet.decimalDigits
        return !key.isEmpty && key.unicodeScalars.allSatisfy(letters.contains)
            && !value.isEmpty && value.unicodeScalars.allSatisfy(digits.contains)
    }

    /// Force the Mac to sleep immediately
    static func sleepNow() throws {
        try ShellExecutor.runDirectWithSudo(pmsetPath, ["sleepnow"])
    }

    /// Restore all original values from backup
    static func restoreValues(_ backup: OriginalSettingsBackup) throws {
        let relevantKeys = Set(SleepSetting.allCases.flatMap(\.pmsetKeys))

        for (key, value) in backup.values where relevantKeys.contains(key) {
            guard isValidPMSetParam(key, value) else {
                throw PMSetError.invalidBackupData(key: key)
            }
            try ShellExecutor.runDirectWithSudo(pmsetPath, ["-a", key, value])
        }
    }

    /// Kill caffeinate processes owned by the current user
    @discardableResult
    static func killCaffeinateProcesses() -> Bool {
        return (try? ShellExecutor.runDirect("/usr/bin/pkill", ["caffeinate"])) != nil
    }
}
