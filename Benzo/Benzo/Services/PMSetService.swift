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
    /// Read current pmset values
    static func readCurrentState() throws -> PMSetState {
        let output = try ShellExecutor.run("pmset -g")
        return PMSetState(parsing: output)
    }

    /// Apply enabled settings
    static func applySettings(_ enabledSettings: [SleepSetting]) throws {
        var commands: [String] = []
        for setting in enabledSettings {
            for (key, value) in setting.pmsetCommands {
                commands.append("/usr/bin/pmset -a \(key) \(value)")
            }
        }

        guard !commands.isEmpty else { return }
        let batchCommand = commands.map { "sudo \($0)" }.joined(separator: " && ")
        try ShellExecutor.runWithAdmin(batchCommand)
    }

    /// Apply enabled settings and restore original values for disabled ones
    static func applySettingsWithRestore(_ enabledSettings: [SleepSetting], disabledSettings: [SleepSetting], backup: OriginalSettingsBackup?) throws {
        var commands: [String] = []

        for setting in enabledSettings {
            for (key, value) in setting.pmsetCommands {
                commands.append("/usr/bin/pmset -a \(key) \(value)")
            }
        }

        if let backup = backup {
            for setting in disabledSettings {
                for key in setting.pmsetKeys {
                    if let originalValue = backup.values[key] {
                        guard isValidPMSetParam(key, originalValue) else {
                            throw PMSetError.invalidBackupData(key: key)
                        }
                        commands.append("/usr/bin/pmset -a \(key) \(originalValue)")
                    }
                }
            }
        }

        guard !commands.isEmpty else { return }
        let batchCommand = commands.map { "sudo \($0)" }.joined(separator: " && ")
        try ShellExecutor.runWithAdmin(batchCommand)
    }

    /// Validate that a pmset key and value are safe for shell interpolation.
    private static func isValidPMSetParam(_ key: String, _ value: String) -> Bool {
        let letters = CharacterSet.letters
        let digits = CharacterSet.decimalDigits
        return !key.isEmpty && key.unicodeScalars.allSatisfy(letters.contains)
            && !value.isEmpty && value.unicodeScalars.allSatisfy(digits.contains)
    }

    /// Force the Mac to sleep immediately
    static func sleepNow() throws {
        try ShellExecutor.runWithAdmin("sudo /usr/bin/pmset sleepnow")
    }

    /// Restore all original values from backup
    static func restoreValues(_ backup: OriginalSettingsBackup) throws {
        let relevantKeys = Set(SleepSetting.allCases.flatMap(\.pmsetKeys))
        var commands: [String] = []

        for (key, value) in backup.values where relevantKeys.contains(key) {
            guard isValidPMSetParam(key, value) else {
                throw PMSetError.invalidBackupData(key: key)
            }
            commands.append("/usr/bin/pmset -a \(key) \(value)")
        }

        guard !commands.isEmpty else { return }
        let batchCommand = commands.map { "sudo \($0)" }.joined(separator: " && ")
        try ShellExecutor.runWithAdmin(batchCommand)
    }

    /// Kill caffeinate processes owned by the current user
    @discardableResult
    static func killCaffeinateProcesses() -> Bool {
        return (try? ShellExecutor.run("pkill caffeinate")) != nil
    }
}
