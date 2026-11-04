import Foundation

enum RecoveryWriteOutcome: Equatable {
    /// The fixed foreground chain returned its operation-bound status.
    /// Configuration still needs separate readback, even for status zero.
    case completed(status: Int)
    case uncertain(String)
}

protocol RecoveryCommanding {
    func capture() async throws -> ProfileSnapshot
    func write(cell: ManagedCell, value: Int, operationID: UUID) async -> RecoveryWriteOutcome
}

/// Pure, closed command vocabulary. Only the app adapter dispatches requests.
enum PMSetService {
    static let captureRequest = CommandRequest(executable: "/usr/bin/pmset",
        arguments: ["-g", "custom"], timeout: 10, maximumOutputBytes: 65_536)

    static func writeRequest(cell: ManagedCell, value: Int, operationID: UUID) throws -> CommandRequest {
        guard cell.key.isValid(value) else {
            throw RecoveryEvidenceError.invalid("The requested setting value is unsupported.")
        }
        // Only enum spellings, a domain-validated Int and an internal UUID enter
        // this fixed foreground script. do-shell-script waits for its command.
        let script = "/usr/bin/pmset \(cell.profile.argument) \(cell.key.rawValue) \(value) >/dev/null 2>&1; " +
            "benzo_status=$?; /usr/bin/printf 'BENZO1:\(operationID.uuidString):%s' \"$benzo_status\""
        let quoted = script.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return CommandRequest(executable: "/usr/bin/osascript",
            arguments: ["-e", "do shell script \"\(quoted)\" with administrator privileges"],
            timeout: 120, maximumOutputBytes: 8_192)
    }

    static func completion(_ outcome: CommandOutcome, operationID: UUID) -> RecoveryWriteOutcome {
        guard outcome.termination == .exited(0), outcome.directChildStopped,
              outcome.outputComplete, !outcome.outputTruncated, outcome.stderr.isEmpty,
              let output = String(data: outcome.stdout, encoding: .utf8) else {
            return .uncertain("The administrator request did not return complete execution evidence. Settings may still change; keep the recovery evidence.")
        }
        let prefix = "BENZO1:\(operationID.uuidString):"
        // osascript prints one line. Extra output cannot be a protocol reply.
        guard output.hasPrefix(prefix), output.hasSuffix("\n") else {
            return .uncertain("The administrator request returned an invalid completion reply.")
        }
        let statusText = String(output.dropFirst(prefix.count).dropLast())
        guard let status = Int(statusText), (0...255).contains(status), String(status) == statusText else {
            return .uncertain("The administrator request returned an invalid completion status.")
        }
        return .completed(status: status)
    }
}
