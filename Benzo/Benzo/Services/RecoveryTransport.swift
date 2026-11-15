import Foundation

/// Reads remain unprivileged. Writes use the exact request already in the GUI
/// fence, then the installed command tool without any interactive fallback.
@MainActor
struct RecoveryTransport: RecoveryCommanding {
    let runner: CommandRunner
    let tool: CommandToolClient

    func capture() async throws -> ProfileSnapshot {
        let result = await runner.run(request: PMSetService.captureRequest)
        guard result.isSuccess, result.directChildStopped, result.stderr.isEmpty,
              let output = String(data: result.stdout, encoding: .utf8) else {
            throw RecoveryEvidenceError.invalid("The complete current power profiles could not be read. No settings were inferred.")
        }
        return try ProfileSnapshot(parsing: output)
    }

    func preflightWrite() async throws { _ = try await tool.version() }
    func prepareWrite(cell: ManagedCell, value: Int, expectedValue: Int,
                      operationID: UUID, bootID: String) async throws -> PowerCommandRequest? {
        try await tool.prepare(cell: cell, value: value, expectedValue: expectedValue,
                               operationID: operationID, bootID: bootID)
    }
    func writePrepared(_ request: PowerCommandRequest) async -> RecoveryWriteOutcome { await tool.write(request) }
    func reconcileWrite(_ request: PowerCommandRequest) async -> RecoveryFenceResolution? { await tool.reconcile(request) }
    func acknowledgeWrite(_ request: PowerCommandRequest) async throws { try await tool.acknowledge(request) }

    func write(cell: ManagedCell, value: Int, expectedValue: Int,
               operationID: UUID, bootID: String) async -> RecoveryWriteOutcome {
        .notExecuted("A durable power request is required before dispatch.")
    }
}
