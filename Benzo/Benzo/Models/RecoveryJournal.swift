import Foundation

struct RecoveryCell: Codable, Equatable {
    let cell: ManagedCell
    let original: Int
    var lastVerified: Int? = nil
    var observed: Int? = nil
    var owned: Bool = true

    private enum CodingKeys: String, CodingKey { case cell, original, lastVerified, observed, owned }
    init(cell: ManagedCell, original: Int, lastVerified: Int? = nil, observed: Int? = nil, owned: Bool = true) {
        self.cell = cell; self.original = original; self.lastVerified = lastVerified
        self.observed = observed; self.owned = owned
    }
    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        cell = try fields.decode(ManagedCell.self, forKey: .cell)
        original = try fields.decode(Int.self, forKey: .original)
        lastVerified = try fields.decode(Int?.self, forKey: .lastVerified)
        observed = try fields.decode(Int?.self, forKey: .observed)
        owned = try fields.decode(Bool.self, forKey: .owned)
    }
    func encode(to encoder: Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(cell, forKey: .cell); try fields.encode(original, forKey: .original)
        try fields.encode(lastVerified, forKey: .lastVerified); try fields.encode(observed, forKey: .observed)
        try fields.encode(owned, forKey: .owned)
    }
}

enum RecoveryStepPhase: String, Codable { case planned, intended, completed, notExecuted, uncertain }

struct RecoveryStep: Codable, Equatable {
    let cell: ManagedCell
    let precondition: Int
    let target: Int
    var phase: RecoveryStepPhase = .planned
    var readback: Int? = nil
    var status: Int? = nil

    private enum CodingKeys: String, CodingKey { case cell, precondition, target, phase, readback, status }
    init(cell: ManagedCell, precondition: Int, target: Int, phase: RecoveryStepPhase = .planned,
         readback: Int? = nil, status: Int? = nil) {
        self.cell = cell; self.precondition = precondition; self.target = target
        self.phase = phase; self.readback = readback; self.status = status
    }
    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        cell = try fields.decode(ManagedCell.self, forKey: .cell)
        precondition = try fields.decode(Int.self, forKey: .precondition)
        target = try fields.decode(Int.self, forKey: .target)
        phase = try fields.decode(RecoveryStepPhase.self, forKey: .phase)
        readback = try fields.decode(Int?.self, forKey: .readback)
        status = try fields.decode(Int?.self, forKey: .status)
    }
    func encode(to encoder: Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(cell, forKey: .cell); try fields.encode(precondition, forKey: .precondition)
        try fields.encode(target, forKey: .target); try fields.encode(phase, forKey: .phase)
        try fields.encode(readback, forKey: .readback); try fields.encode(status, forKey: .status)
    }
}

enum RecoveryOperationKind: String, Codable { case apply, restore, compensate, conflictRestore }
struct RecoveryOperation: Codable, Equatable {
    let id: UUID
    let bootID: String
    let kind: RecoveryOperationKind
    let preState: [CellValue]
    var steps: [RecoveryStep]
}

struct RecoveryJournal: Codable, Equatable {
    let schema: Int
    let uid: UInt32
    let hostID: String
    let sessionID: UUID
    var revision: Int
    let capturedAt: Date
    let capture: ProfileSnapshot
    let selectedSettings: [String]
    let profiles: [PowerProfile]
    var cells: [RecoveryCell]
    var operation: RecoveryOperation?
    var resolvedAt: Date?

    init(schema: Int = 1, uid: UInt32, hostID: String, sessionID: UUID, revision: Int,
         capturedAt: Date, capture: ProfileSnapshot, selectedSettings: [String],
         profiles: [PowerProfile], cells: [RecoveryCell], operation: RecoveryOperation? = nil,
         resolvedAt: Date? = nil) {
        self.schema = schema; self.uid = uid; self.hostID = hostID; self.sessionID = sessionID
        self.revision = revision; self.capturedAt = capturedAt; self.capture = capture
        self.selectedSettings = selectedSettings; self.profiles = profiles; self.cells = cells
        self.operation = operation; self.resolvedAt = resolvedAt
    }

    func validate(uid expectedUID: UInt32, hostID expectedHost: String) throws {
        guard schema == 1, uid == expectedUID, hostID == expectedHost,
              UUID(uuidString: hostID) != nil, hostID.utf8.count == 36,
              revision > 0, capturedAt.timeIntervalSince1970.isFinite,
              !selectedSettings.isEmpty, selectedSettings.count <= SleepSetting.allCases.count,
              Set(selectedSettings).count == selectedSettings.count,
              profiles == capture.profiles, !profiles.isEmpty,
              cells.count <= 21, Set(cells.map(\.cell)).count == cells.count,
              cells.map(\.cell) == cells.map(\.cell).sorted(),
              try ProfileSnapshot(parsing: capture.raw) == capture else {
            throw RecoveryEvidenceError.invalid("Recovery journal identity, schema or capture is invalid.")
        }
        var targets: [ManagedKey: Int] = [:]
        for name in selectedSettings {
            guard let setting = SleepSetting(rawValue: name) else {
                throw RecoveryEvidenceError.invalid("Recovery journal contains an unknown setting selection.")
            }
            for command in setting.pmsetCommands {
                guard let key = ManagedKey(rawValue: command.key), let target = Int(command.value), key.isValid(target) else {
                    throw RecoveryEvidenceError.invalid("Recovery journal contains an invalid target.")
                }
                targets[key] = target
            }
        }
        for profile in profiles {
            for key in targets.keys {
                guard capture.value(for: ManagedCell(profile: profile, key: key)) != nil else {
                    throw RecoveryEvidenceError.invalid("Recovery journal is missing a selected original value.")
                }
            }
        }
        let expectedCells = profiles.flatMap { profile in targets.compactMap { key, target -> ManagedCell? in
            let cell = ManagedCell(profile: profile, key: key)
            return capture.value(for: cell) == target ? nil : cell
        }}.sorted()
        guard cells.map(\.cell) == expectedCells else {
            throw RecoveryEvidenceError.invalid("Recovery journal does not preserve every changed selected cell.")
        }
        for cell in cells {
            guard cell.original == capture.value(for: cell.cell), cell.cell.key.isValid(cell.original),
                  cell.lastVerified.map(cell.cell.key.isValid) ?? true,
                  cell.observed.map(cell.cell.key.isValid) ?? true else {
                throw RecoveryEvidenceError.invalid("Recovery journal has inconsistent original or observed values.")
            }
        }
        if let operation {
            let cellSet = Set(cells.map(\.cell))
            guard operation.bootID.utf8.count == 36, UUID(uuidString: operation.bootID) != nil,
                  operation.steps.count <= cells.count,
                  Set(operation.steps.map(\.cell)).count == operation.steps.count,
                  operation.preState.count <= 21,
                  Set(operation.preState.map(\.cell)).count == operation.preState.count,
                  operation.preState.allSatisfy({ profiles.contains($0.cell.profile) && $0.cell.key.isValid($0.value) }) else {
                throw RecoveryEvidenceError.invalid("Recovery operation contains duplicate or invalid cells.")
            }
            for step in operation.steps {
                guard cellSet.contains(step.cell), step.cell.key.isValid(step.precondition), step.cell.key.isValid(step.target),
                      step.readback.map(step.cell.key.isValid) ?? true,
                      step.status.map({ (0...255).contains($0) }) ?? true,
                      operation.preState.contains(where: { $0.cell == step.cell && $0.value == step.precondition }) else {
                    throw RecoveryEvidenceError.invalid("Recovery operation has invalid or missing preconditions.")
                }
                if (step.phase == .planned || step.phase == .notExecuted) && (step.status != nil || step.readback != nil) {
                    throw RecoveryEvidenceError.invalid("An unattempted recovery step has a fabricated outcome.")
                }
                if step.phase == .completed && step.status == nil {
                    throw RecoveryEvidenceError.invalid("A completed recovery step is missing execution evidence.")
                }
            }
        }
        if let resolvedAt {
            guard resolvedAt.timeIntervalSince1970.isFinite, resolvedAt >= capturedAt,
                  !cells.contains(where: \.owned),
                  !(operation?.steps.contains(where: { $0.phase == .intended || $0.phase == .uncertain }) ?? false) else {
                throw RecoveryEvidenceError.invalid("A resolved journal still contains unresolved ownership or execution.")
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schema, uid, hostID, sessionID, revision, capturedAt, capture, selectedSettings, profiles, cells, operation, resolvedAt
    }
    init(from decoder: Decoder) throws {
        let f = try decoder.container(keyedBy: CodingKeys.self)
        schema = try f.decode(Int.self, forKey: .schema); uid = try f.decode(UInt32.self, forKey: .uid)
        hostID = try f.decode(String.self, forKey: .hostID); sessionID = try f.decode(UUID.self, forKey: .sessionID)
        revision = try f.decode(Int.self, forKey: .revision); capturedAt = try f.decode(Date.self, forKey: .capturedAt)
        capture = try f.decode(ProfileSnapshot.self, forKey: .capture)
        selectedSettings = try f.decode([String].self, forKey: .selectedSettings)
        profiles = try f.decode([PowerProfile].self, forKey: .profiles); cells = try f.decode([RecoveryCell].self, forKey: .cells)
        operation = try f.decode(RecoveryOperation?.self, forKey: .operation); resolvedAt = try f.decode(Date?.self, forKey: .resolvedAt)
    }
    func encode(to encoder: Encoder) throws {
        var f = encoder.container(keyedBy: CodingKeys.self)
        try f.encode(schema, forKey: .schema); try f.encode(uid, forKey: .uid); try f.encode(hostID, forKey: .hostID)
        try f.encode(sessionID, forKey: .sessionID); try f.encode(revision, forKey: .revision)
        try f.encode(capturedAt, forKey: .capturedAt); try f.encode(capture, forKey: .capture)
        try f.encode(selectedSettings, forKey: .selectedSettings); try f.encode(profiles, forKey: .profiles)
        try f.encode(cells, forKey: .cells); try f.encode(operation, forKey: .operation); try f.encode(resolvedAt, forKey: .resolvedAt)
    }
}
