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

    init(schema: Int = 1, uid: UInt32, hostID: String, bootID: String, incarnationID: UUID,
         sessionID: UUID, operationID: UUID, cell: ManagedCell, target: Int, completed: Bool) {
        self.schema = schema; self.uid = uid; self.hostID = hostID; self.bootID = bootID
        self.incarnationID = incarnationID; self.sessionID = sessionID; self.operationID = operationID
        self.cell = cell; self.target = target; self.completed = completed
    }

    func validate(uid expectedUID: UInt32, hostID expectedHost: String) throws {
        guard schema == 1, uid == expectedUID, hostID == expectedHost,
              hostID.utf8.count == 36, UUID(uuidString: hostID) != nil,
              bootID.utf8.count == 36, UUID(uuidString: bootID) != nil, cell.key.isValid(target) else {
            throw RecoveryEvidenceError.invalid("Execution fence identity, schema or target is invalid.")
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
    func loadLegacyEvidence() throws -> Data?
}

enum PersistenceBoundary: CaseIterable {
    case write, fileSync, fileFullSync, fileClose, previousRename, rename
    case directorySync, directoryFullSync, directoryClose
    case completionMarkerRemove
}
