import Foundation

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
                        commands.append("/usr/bin/pmset -a \(key) \(originalValue)")
                    }
                }
            }
        }

        guard !commands.isEmpty else { return }
        let batchCommand = commands.map { "sudo \($0)" }.joined(separator: " && ")
        try ShellExecutor.runWithAdmin(batchCommand)
    }

    /// Restore all original values from backup
    static func restoreValues(_ backup: OriginalSettingsBackup) throws {
        let relevantKeys = Set(SleepSetting.allCases.flatMap(\.pmsetKeys))
        var commands: [String] = []

        for (key, value) in backup.values where relevantKeys.contains(key) {
            commands.append("/usr/bin/pmset -a \(key) \(value)")
        }

        guard !commands.isEmpty else { return }
        let batchCommand = commands.map { "sudo \($0)" }.joined(separator: " && ")
        try ShellExecutor.runWithAdmin(batchCommand)
    }
}
