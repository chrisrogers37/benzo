import Foundation

/// Legacy synchronous transport, retained until the complete recovery boundary in phase 02.
enum ShellExecutor {
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
        _ = try runDirect(BenzoPaths.sudo, ["-n", executable] + args)
    }
}

/// Live command adapter. Excluded from the unhosted core test target.
struct ShellCommandRunner: CommandRunning {
    func runDirect(_ executable: String, _ arguments: [String]) throws -> String {
        try ShellExecutor.runDirect(executable, arguments)
    }

    func runDirectWithSudo(_ executable: String, _ arguments: [String]) throws {
        try ShellExecutor.runDirectWithSudo(executable, arguments)
    }
}
