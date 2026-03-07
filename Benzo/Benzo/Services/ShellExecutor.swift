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

    /// Check if passwordless pmset access is installed
    static var isSetupComplete: Bool {
        FileManager.default.fileExists(atPath: sudoersPath)
    }

    /// One-time setup: install sudoers rule granting passwordless pmset access
    static func installSudoersRule() throws {
        let rule = "%admin ALL=(root) NOPASSWD: /usr/bin/pmset\n"
        let command = "echo '\(rule)' > \(sudoersPath) && chmod 0440 \(sudoersPath)"
        try runWithOsascript(command)
    }

    /// Remove the sudoers rule (for uninstall/cleanup)
    static func removeSudoersRule() throws {
        try runWithOsascript("rm -f \(sudoersPath)")
    }

    /// Run a shell command without privileges
    static func run(_ command: String) throws -> String {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Run a pmset command using sudo (no password needed after setup)
    static func runWithAdmin(_ command: String) throws {
        if isSetupComplete {
            try runWithSudo(command)
        } else {
            try runWithOsascript(command)
        }
    }

    // MARK: - Private

    /// Run via sudo (passwordless after sudoers rule installed)
    private static func runWithSudo(_ command: String) throws {
        let process = Process()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw ShellError.executionFailed(errorMessage.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

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
