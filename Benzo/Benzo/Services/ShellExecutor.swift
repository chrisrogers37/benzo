import Foundation

enum ShellError: LocalizedError {
    case userCancelled
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .userCancelled:
            return "Authentication was cancelled."
        case .executionFailed(let message):
            return message
        }
    }
}

enum ShellExecutor {
    private static let sudoersPath = "/etc/sudoers.d/benzo"
    private static let sudoersVersionKey = "sudoersRuleVersion"

    /// Bump when the sudoers rule body changes to trigger migration on next launch.
    static let currentSudoersRuleVersion = 2

    /// Check if passwordless pmset access is installed
    static var isSetupComplete: Bool {
        FileManager.default.fileExists(atPath: sudoersPath)
    }

    /// True when the sudoers file is missing, an older version, or no longer functional.
    /// The functional probe catches manual edits / corruption that the version marker can't see.
    static var needsSudoersUpdate: Bool {
        guard isSetupComplete else { return false }
        if UserDefaults.standard.integer(forKey: sudoersVersionKey) < currentSudoersRuleVersion {
            return true
        }
        return !sudoersRuleFunctional()
    }

    /// Cheap probe: does `sudo -n /usr/bin/pmset -g` succeed?
    /// If yes, the NOPASSWD rule is in place and grants the access we expect.
    private static func sudoersRuleFunctional() -> Bool {
        do {
            _ = try runDirect("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-g"])
            return true
        } catch {
            return false
        }
    }

    /// One-time setup: install sudoers rule granting passwordless pmset access
    /// for exactly the subcommands Benzo uses. Validated with `visudo -cf` before
    /// install so a malformed rule never lands in /etc/sudoers.d/.
    static func installSudoersRule() throws {
        let rule = buildSudoersRule()
        let script = """
        set -e
        tmp=$(/usr/bin/mktemp /tmp/benzo-sudoers.XXXXXX)
        /bin/cat > "$tmp" <<'BENZO_SUDOERS'
        \(rule)
        BENZO_SUDOERS
        /usr/sbin/visudo -cf "$tmp"
        /usr/bin/install -m 0440 -o root -g wheel "$tmp" \(sudoersPath)
        /bin/rm -f "$tmp"
        """
        try runWithOsascript(script)
        UserDefaults.standard.set(currentSudoersRuleVersion, forKey: sudoersVersionKey)
    }

    /// Remove the sudoers rule (for uninstall/cleanup)
    static func removeSudoersRule() throws {
        try runWithOsascript("rm -f \(sudoersPath)")
        UserDefaults.standard.removeObject(forKey: sudoersVersionKey)
    }

    /// Build the sudoers rule body from `SleepSetting.allCases` so the allowlist
    /// stays in sync with the keys Benzo actually writes.
    private static func buildSudoersRule() -> String {
        let keys = SleepSetting.allCases.flatMap(\.pmsetKeys).sorted()
        var entries = ["/usr/bin/pmset sleepnow"]
        entries.append(contentsOf: keys.map { "/usr/bin/pmset -a \($0) [0-9]*" })
        return """
        Cmnd_Alias BENZO_PMSET = \(entries.joined(separator: ", "))
        %admin ALL=(root) NOPASSWD: BENZO_PMSET
        """
    }

    /// Run an executable directly with arguments — no shell, no interpolation.
    /// stderr is merged into the returned output so failure messages survive.
    @discardableResult
    static func runDirect(_ executable: String, _ args: [String] = []) throws -> String {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw ShellError.executionFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }

    /// Run an executable via passwordless sudo. `-n` makes sudo fail fast rather
    /// than prompting, so a missing/broken sudoers rule surfaces as an error.
    static func runDirectWithSudo(_ executable: String, _ args: [String] = []) throws {
        _ = try runDirect("/usr/bin/sudo", ["-n", executable] + args)
    }

    // MARK: - Private

    /// Run via osascript (prompts for password)
    private static func runWithOsascript(_ command: String) throws {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = "do shell script \"\(escaped)\" with administrator privileges with prompt \"Benzo needs a one-time setup to control sleep settings.\""

        let process = Process()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"

            if errorMessage.contains("User canceled") || process.terminationStatus == 1 {
                throw ShellError.userCancelled
            }
            throw ShellError.executionFailed(errorMessage.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
