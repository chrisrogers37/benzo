import Foundation

/// App-only reads remain unprivileged. Every write goes through the authenticated
/// helper; there is no AppleScript or sudo fallback when setup is unavailable.
@MainActor
struct RecoveryTransport: RecoveryCommanding {
    let runner: CommandRunner
    let helper: HelperServiceClient

    func capture() async throws -> ProfileSnapshot {
        let result = await runner.run(request: PMSetService.captureRequest)
        guard result.isSuccess, result.directChildStopped, result.stderr.isEmpty,
              let output = String(data: result.stdout, encoding: .utf8) else {
            throw RecoveryEvidenceError.invalid("The complete current power profiles could not be read. No settings were inferred.")
        }
        return try ProfileSnapshot(parsing: output)
    }

    func preflightWrite() async throws { _ = try await helper.writableStatus() }

    func write(cell: ManagedCell, value: Int, expectedValue: Int,
               operationID: UUID, bootID: String) async -> RecoveryWriteOutcome {
        let status: HelperStatus
        do {
            guard cell.key.isValid(value), cell.key.isValid(expectedValue) else {
                return .notExecuted("The requested setting value is unsupported.")
            }
            status = try await helper.writableStatus()
            guard UUID(uuidString: status.bootID) == UUID(uuidString: bootID) else {
                return .notExecuted("The helper boot identity changed before dispatch.")
            }
        } catch {
            // Only status was requested. No setting command was sent.
            return .notExecuted(error.localizedDescription)
        }
        let request = HelperWriteRequest(requestID: UUID(), operationID: operationID,
            bootID: bootID, cell: cell, expectedValue: expectedValue, target: value,
            expectedRevision: status.revision)
        return await helper.sendWrite(request)
    }
}
