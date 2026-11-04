import Foundation

/// App-only adapter over the existing bounded process engine.
struct RecoveryTransport: RecoveryCommanding {
    let runner: CommandRunner

    func capture() async throws -> ProfileSnapshot {
        let result = await runner.run(request: PMSetService.captureRequest)
        guard result.isSuccess, result.directChildStopped, result.stderr.isEmpty,
              let output = String(data: result.stdout, encoding: .utf8) else {
            throw RecoveryEvidenceError.invalid("The complete current power profiles could not be read. No settings were inferred.")
        }
        return try ProfileSnapshot(parsing: output)
    }

    func write(cell: ManagedCell, value: Int, operationID: UUID) async -> RecoveryWriteOutcome {
        do {
            let request = try PMSetService.writeRequest(cell: cell, value: value, operationID: operationID)
            return PMSetService.completion(await runner.run(request: request), operationID: operationID)
        } catch {
            // Coordinator validates before intent. A contract violation still must
            // not clear an already durable fence.
            return .uncertain(error.localizedDescription)
        }
    }
}
