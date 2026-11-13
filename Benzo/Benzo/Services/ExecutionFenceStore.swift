import Foundation

struct ExecutionFence: Codable, Equatable {
    let schema: Int
    let uid: UInt32
    let hostID: String
    let bootID: String
    let incarnationID: UUID
    let sessionID: UUID
    let operationID: UUID
    let cell: ManagedCell
    let target: Int
    var completed: Bool
    let commandRequest: PowerCommandRequest?
    /// Optional for old fences. Once true, the root receipt has been consumed
    /// and later read-only reconciliation need not contact an uninstalled tool.
    var commandAcknowledged: Bool?

    init(schema: Int = 1, uid: UInt32, hostID: String, bootID: String, incarnationID: UUID,
         sessionID: UUID, operationID: UUID, cell: ManagedCell, target: Int, completed: Bool,
         commandRequest: PowerCommandRequest? = nil, commandAcknowledged: Bool = false) {
        self.schema = schema; self.uid = uid; self.hostID = hostID; self.bootID = bootID
        self.incarnationID = incarnationID; self.sessionID = sessionID; self.operationID = operationID
        self.cell = cell; self.target = target; self.completed = completed
        self.commandRequest = commandRequest
        self.commandAcknowledged = commandRequest == nil ? nil : commandAcknowledged
    }

    func validate(uid expectedUID: UInt32, hostID expectedHost: String) throws {
        guard schema == 1, uid == expectedUID, hostID == expectedHost,
              hostID.utf8.count == 36, UUID(uuidString: hostID) != nil,
              bootID.utf8.count == 36, UUID(uuidString: bootID) != nil, cell.key.isValid(target) else {
            throw RecoveryEvidenceError.invalid("Execution fence identity, schema or target is invalid.")
        }
        if let commandRequest {
            try commandRequest.validate()
            guard commandRequest.operationID == operationID,
                  commandRequest.bootID == UUID(uuidString: bootID),
                  commandRequest.cell == cell, commandRequest.target == target else {
                throw RecoveryEvidenceError.invalid("The persisted power request does not match its recovery fence.")
            }
        }
        guard commandAcknowledged != true || (commandRequest != nil && completed) else {
            throw RecoveryEvidenceError.invalid("Acknowledgement cannot precede durable command completion.")
        }
    }
}

protocol RecoveryStoring: AnyObject {
    func acquireLock() throws
    func loadJournal() throws -> RecoveryJournal?
    func commitJournal(_ journal: RecoveryJournal) throws
    func saveResolvedReceipt(_ journal: RecoveryJournal) throws
    func loadFence() throws -> ExecutionFence?
    func commitFence(_ fence: ExecutionFence) throws
    /// Only call after an authenticated command receipt proves completion or
    /// later-boot reconciliation. This can repair an interrupted local barrier.
    func commitVerifiedCommandFence(_ fence: ExecutionFence) throws
    func loadLegacyEvidence() throws -> Data?
}

extension RecoveryStoring {
    func commitVerifiedCommandFence(_ fence: ExecutionFence) throws { try commitFence(fence) }
}

enum PersistenceBoundary: CaseIterable {
    case write, fileSync, fileFullSync, fileClose, previousRename, rename
    case directorySync, directoryFullSync, directoryClose
    case completionMarkerRemove
}
