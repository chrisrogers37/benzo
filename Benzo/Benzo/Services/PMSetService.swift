import Foundation

enum RecoveryWriteOutcome: Equatable {
    /// A terminal, operation-bound helper receipt; readback is still required.
    case completed(status: Int)
    /// Authenticated evidence that this request was rejected before execution.
    case notExecuted(String)
    case uncertain(String)
}

enum RecoveryFenceResolution: Equatable {
    case terminal(RecoveryWriteOutcome)
    /// A verified later boot proves the old child stopped, not its exit status.
    case stoppedOnLaterBoot
}

protocol RecoveryCommanding {
    func capture() async throws -> ProfileSnapshot
    /// Check access before persisting intent. The write still checks admission again.
    func preflightWrite() async throws
    func write(cell: ManagedCell, value: Int, expectedValue: Int,
               operationID: UUID, bootID: String) async -> RecoveryWriteOutcome
    func prepareWrite(cell: ManagedCell, value: Int, expectedValue: Int,
                      operationID: UUID, bootID: String) async throws -> PowerCommandRequest?
    func writePrepared(_ request: PowerCommandRequest) async -> RecoveryWriteOutcome
    func reconcileWrite(_ request: PowerCommandRequest) async -> RecoveryFenceResolution?
    func acknowledgeWrite(_ request: PowerCommandRequest) async throws
}

extension RecoveryCommanding {
    // Old/injected transports retain conservative fencing rather than inventing
    // command-tool receipts for evidence created before this protocol existed.
    func prepareWrite(cell: ManagedCell, value: Int, expectedValue: Int,
                      operationID: UUID, bootID: String) async throws -> PowerCommandRequest? { nil }
    func writePrepared(_ request: PowerCommandRequest) async -> RecoveryWriteOutcome {
        .uncertain("This transport cannot dispatch a persisted power request.")
    }
    func reconcileWrite(_ request: PowerCommandRequest) async -> RecoveryFenceResolution? { nil }
    func acknowledgeWrite(_ request: PowerCommandRequest) async throws {}
}

extension PowerCommandReply {
    func recoveryOutcome(for expected: PowerCommandRequest) throws -> RecoveryWriteOutcome {
        guard schema == 1, protocolVersion == 1, token == expected.token, request == expected else {
            throw PowerCommandError.invalid("The power result does not match its saved request.")
        }
        switch outcome {
        case .completed(let status) where (0...255).contains(status): return .completed(status: status)
        case .notExecuted(let reason):
            try PowerCommandWire.validateReason(reason)
            return .notExecuted(reason)
        default: return .uncertain("The saved power request has no terminal execution evidence.")
        }
    }

    func recoveryResolution(for expected: PowerCommandRequest) throws -> RecoveryFenceResolution? {
        guard schema == 1, protocolVersion == 1, token == expected.token else {
            throw PowerCommandError.invalid("The power result does not match its saved token.")
        }
        guard request == expected else { return nil }
        switch outcome {
        case .completed, .notExecuted: return .terminal(try recoveryOutcome(for: expected))
        case .reconciledAfterBoot(let value):
            guard expected.key.isValid(value), let bootID, bootID != expected.bootID else {
                throw PowerCommandError.invalid("The previous request has not been reconciled on a later boot.")
            }
            return .stoppedOnLaterBoot
        default: return nil
        }
    }
}

/// Pure, closed command vocabulary. Only the installed tool executes writes.
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
