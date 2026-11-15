import Foundation

/// Separate from the settings journal: sleeping must not replace the successful
/// apply operation, captured originals, or last-verified setting ownership.
struct SleepIntent: Codable, Equatable {
    var schema = 1
    let uid: UInt32
    let hostID: String
    let sessionID: UUID
    let request: PowerSleepRequest
    var terminal: PowerSleepReceipt?
    var acknowledged = false

    func validate(uid expectedUID: UInt32, hostID expectedHost: String) throws {
        try request.validate()
        guard schema == 1, uid == expectedUID, hostID == expectedHost,
              UUID(uuidString: hostID) != nil, sessionID != PowerCommandWire.zeroUUID else {
            throw RecoveryEvidenceError.invalid("The saved sleep request has an invalid identity.")
        }
        if let terminal {
            try terminal.validate()
            guard terminal.request == request, terminal.isTerminal else {
                throw RecoveryEvidenceError.invalid("The sleep result does not prove that its command stopped.")
            }
        }
        guard !acknowledged || terminal != nil else {
            throw RecoveryEvidenceError.invalid("Sleep acknowledgement requires a durable terminal result.")
        }
    }
}

extension PowerSleepReceipt {
    var message: String {
        switch outcome {
        case .intent: return "The sleep request is pending. Refresh recovery to check its saved result."
        case .completed(let status):
            return status == 0 ? "Sleep was requested. Physical sleep is not verified." : "The sleep command stopped with status \(status). Physical sleep is not verified."
        case .notExecuted(let reason): return "Sleep was not requested. " + reason
        case .childStoppedOutcomeUnknown, .reconciledAfterBoot:
            return "The sleep command has stopped. Its physical sleep result is unknown."
        }
    }
}

extension PowerCommandReply {
    func sleepReceipt(for expected: PowerSleepRequest) throws -> PowerSleepReceipt? {
        guard schema == 2, protocolVersion == 1, token == expected.token else {
            throw PowerCommandError.invalid("The sleep reply does not match its saved token.")
        }
        guard sleepRequest == expected, let receipt = pendingSleep, receipt.request == expected else { return nil }
        try receipt.validate()
        if case .reconciledAfterBoot = receipt.outcome {
            guard let bootID, bootID != expected.bootID else {
                throw PowerCommandError.invalid("The sleep request has not stopped on a verified later boot.")
            }
        }
        return receipt
    }
}
