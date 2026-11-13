import Foundation

enum RecoveryWriteOutcome: Equatable {
    /// A terminal, operation-bound helper receipt; readback is still required.
    case completed(status: Int)
    /// Authenticated evidence that this request was rejected before execution.
    case notExecuted(String)
    case uncertain(String)
}

protocol RecoveryCommanding {
    func capture() async throws -> ProfileSnapshot
    /// Check access before persisting intent. The write still checks admission again.
    func preflightWrite() async throws
    func write(cell: ManagedCell, value: Int, expectedValue: Int,
               operationID: UUID, bootID: String) async -> RecoveryWriteOutcome
}

/// Pure, closed command vocabulary. The daemon alone executes setting writes.
enum PMSetService {
    static let captureRequest = CommandRequest(executable: "/usr/bin/pmset",
        arguments: ["-g", "custom"], timeout: 10, maximumOutputBytes: 65_536)

    static func writeRequest(cell: ManagedCell, value: Int) throws -> CommandRequest {
        guard cell.key.isValid(value) else {
            throw RecoveryEvidenceError.invalid("The requested setting value is unsupported.")
        }
        return CommandRequest(executable: "/usr/bin/pmset",
            arguments: [cell.profile.argument, cell.key.rawValue, String(value)],
            timeout: 20, maximumOutputBytes: 8_192)
    }

    static func completion(_ outcome: CommandOutcome) -> RecoveryWriteOutcome {
        guard outcome.directChildStopped, outcome.outputComplete, !outcome.outputTruncated,
              case .exited(let status) = outcome.termination, (0...255).contains(status) else {
            return .uncertain("The helper could not establish that the setting command finished. Recovery evidence was retained.")
        }
        return .completed(status: Int(status))
    }
}
