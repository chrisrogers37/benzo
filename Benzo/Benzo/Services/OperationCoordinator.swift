import Foundation

enum ConflictChoice { case keepCurrent, restoreOriginal }

/// One admission token spans every await, including authorization, compensation
/// and persistence. The account lock is retained by the store for its lifetime.
@MainActor
final class OperationCoordinator {
    private(set) var state: ControlState = .checking
    private(set) var conflicts: [RecoveryConflict] = []
    private(set) var unavailable: [SleepSetting: String] = [:]
    private(set) var executionUncertain = false
    var hasSession: Bool { journal.map { $0.resolvedAt == nil } ?? false }
    var frozenSettings: [SleepSetting]? {
        hasSession ? journal?.selectedSettings.compactMap(SleepSetting.init(rawValue:)) : nil
    }
    var capturedAt: Date? { hasSession ? journal?.capturedAt : nil }
    var onChange: (() -> Void)?

    private let store: any RecoveryStoring
    private let transport: any RecoveryCommanding
    private let uid: UInt32
    private let hostID: String
    private let bootID: () throws -> String
    private let now: () -> Date
    private let legacyActive: () -> Bool
    private let legacyRule: () -> PermissionObservation
    private let incarnationID = UUID()
    private var journal: RecoveryJournal?
    private var admitted = false
    private var quitRequested = false
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    /// An in-process persistence failure cannot be laundered by rereading a file
    /// that happened to reach rename before its final durability check failed.
    private var uncertainBoot: String?

    init(store: any RecoveryStoring, transport: any RecoveryCommanding, uid: UInt32,
         hostID: String, bootID: @escaping () throws -> String, now: @escaping () -> Date,
         legacyActive: @escaping () -> Bool, legacyRule: @escaping () -> PermissionObservation) {
        self.store = store; self.transport = transport; self.uid = uid; self.hostID = hostID
        self.bootID = bootID; self.now = now; self.legacyActive = legacyActive; self.legacyRule = legacyRule
    }

    func reconcile() async {
        guard begin() else { return }
        defer { end() }
        publish(.checking)
        do { try await reconcileAdmitted() }
        catch { fail(error) }
    }

    func apply(settings: [SleepSetting]) async {
        guard !quitRequested, begin() else { return }
        defer { end() }
        publish(.checking)
        do {
            try await reconcileAdmitted()
            guard state == .off, !executionUncertain else { return }
            guard !settings.isEmpty, Set(settings).count == settings.count else {
                throw invalid("Choose at least one available setting before applying.")
            }
            let boot = try currentBoot()
            let capture = try await transport.capture()
            updateAvailability(capture)
            guard settings.allSatisfy({ unavailable[$0] == nil }) else {
                throw invalid("A selected setting is unavailable in a reported power profile. No settings were changed.")
            }
            let targets = try targetValues(settings, profiles: capture.profiles)
            var cells: [RecoveryCell] = []
            var steps: [RecoveryStep] = []
            for target in targets {
                guard let original = capture.value(for: target.cell) else {
                    throw invalid("A selected original value is missing. No settings were changed.")
                }
                if original != target.value {
                    cells.append(RecoveryCell(cell: target.cell, original: original, observed: original))
                    steps.append(RecoveryStep(cell: target.cell, precondition: original, target: target.value))
                }
            }
            let plan = RecoveryOperation(id: UUID(), bootID: boot, kind: .apply, preState: capture.values, steps: steps)
            let session = RecoveryJournal(uid: uid, hostID: hostID, sessionID: UUID(), revision: 1,
                capturedAt: now(), capture: capture, selectedSettings: settings.map(\.rawValue),
                profiles: capture.profiles, cells: cells, operation: plan)
            try store.commitJournal(session)
            journal = session
            publish(.applying)
            do {
                try await execute(plan)
                let readback = try await transport.capture()
                guard targets.allSatisfy({ readback.value(for: $0.cell) == $0.value }) else {
                    throw invalid("Final readback differs from the frozen selection.")
                }
                if cells.isEmpty { try finishResolved() }
                else { publish(.activeVerified(now())) }
            } catch {
                await recoverFailedOperation(plan, cause: error)
            }
        } catch { fail(error) }
    }

    func restore() async {
        guard begin() else { return }
        defer { end() }
        publish(.checking)
        do {
            try await reconcileAdmitted()
            guard hasSession, !executionUncertain else { return }
            guard conflicts.isEmpty else { throw invalid("Resolve or defer the conflicting settings before restoring.") }
            guard let current = journal else { return }
            let capture = try await transport.capture()
            let steps = try current.cells.filter(\.owned).map { cell -> RecoveryStep in
                guard let value = capture.value(for: cell.cell), value == cell.lastVerified else {
                    throw invalid("A setting changed before restoration. Refresh recovery to inspect the conflict.")
                }
                return RecoveryStep(cell: cell.cell, precondition: value, target: cell.original)
            }
            let plan = RecoveryOperation(id: UUID(), bootID: try currentBoot(), kind: .restore, preState: capture.values.filter { current.profiles.contains($0.cell.profile) }, steps: steps)
            try install(plan)
            publish(.restoring)
            do {
                try await execute(plan)
                try await reconcileAdmitted()
                guard state == .off else { throw invalid("Some captured settings still need recovery.") }
            } catch { await recoverFailedOperation(plan, cause: error) }
        } catch { fail(error) }
    }

    func resolveConflict(_ cell: ManagedCell, choice: ConflictChoice) async {
        guard begin() else { return }
        defer { end() }
        do {
            try await reconcileAdmitted()
            guard !executionUncertain, conflicts.contains(where: { $0.cell == cell }),
                  var current = journal, let index = current.cells.firstIndex(where: { $0.cell == cell && $0.owned }) else { return }
            let capture = try await transport.capture()
            // A disappeared profile cannot be accepted as a known current value.
            guard let value = capture.value(for: cell) else { throw invalid("This profile or setting is not currently observable. Recovery evidence was preserved.") }
            switch choice {
            case .keepCurrent:
                current.cells[index].observed = value
                current.cells[index].owned = false
                try commit(current)
                try await reconcileAdmitted()
            case .restoreOriginal:
                let plan = RecoveryOperation(id: UUID(), bootID: try currentBoot(), kind: .conflictRestore, preState: capture.values.filter { current.profiles.contains($0.cell.profile) },
                    steps: [RecoveryStep(cell: cell, precondition: value, target: current.cells[index].original)])
                try install(plan)
                publish(.restoring)
                do {
                    try await execute(plan)
                    try await reconcileAdmitted()
                } catch { await recoverFailedOperation(plan, cause: error) }
            }
        } catch { fail(error) }
    }

    func mayEditSelections() -> Bool {
        guard !admitted, !quitRequested, state == .off, !executionUncertain else { return false }
        guard begin() else { return false }
        defer { end() }
        do {
            try store.acquireLock()
            let loaded = try store.loadJournal()
            try checkLegacy(loaded)
            guard loaded == journal, loaded?.resolvedAt != nil || loaded == nil,
                  try isQuiescent(loaded, fence: store.loadFence(), boot: currentBoot()) else {
                throw invalid("Recovery evidence changed. Refresh before editing selections.")
            }
            return true
        } catch { fail(error); return false }
    }

    func waitUntilIdle() async {
        if admitted { await withCheckedContinuation { idleWaiters.append($0) } }
    }

    func prepareToQuit() async -> Bool {
        quitRequested = true
        defer { quitRequested = false }
        await waitUntilIdle()
        await restore()
        return state == .off && !executionUncertain
    }

    private func begin() -> Bool {
        guard !admitted else { return false }
        admitted = true
        return true
    }

    private func end() {
        admitted = false
        let waiters = idleWaiters
        idleWaiters.removeAll()
        waiters.forEach { $0.resume() }
        onChange?()
    }

    private func publish(_ value: ControlState) { state = value; onChange?() }
    private func fail(_ error: Error) { publish(.recoveryRequired(error.localizedDescription)) }
    private func invalid(_ message: String) -> RecoveryEvidenceError { .invalid(message) }

    private func currentBoot() throws -> String {
        let value = try bootID()
        guard value.utf8.count == 36, let uuid = UUID(uuidString: value) else {
            throw invalid("The current boot cannot be identified. Execution remains unknown.")
        }
        return uuid.uuidString
    }

    private func sameBoot(_ first: String, _ second: String) -> Bool {
        UUID(uuidString: first) == UUID(uuidString: second)
    }

    private func checkLegacy(_ loaded: RecoveryJournal?) throws {
        guard try store.loadLegacyEvidence() == nil, legacyRule() == .noLegacyRule,
              loaded != nil || !legacyActive() else {
            throw invalid("Legacy or unknown recovery evidence needs administrator-assisted recovery and retirement. Preserve ~/Library/Application Support/Benzo/original-pmset.json and /private/etc/sudoers.d/benzo. This app cannot substantiate their profile ownership or mark them restored.")
        }
    }

    private func isQuiescent(_ loaded: RecoveryJournal?, fence: ExecutionFence?, boot: String) throws -> Bool {
        if let uncertainBoot, sameBoot(uncertainBoot, boot) { return false }
        if let fence {
            try fence.validate(uid: uid, hostID: hostID)
            if !fence.completed && sameBoot(fence.bootID, boot) { return false }
        }
        if let operation = loaded?.operation {
            for step in operation.steps where step.phase == .intended || step.phase == .uncertain {
                if !sameBoot(operation.bootID, boot) { continue }
                guard let fence, fence.completed, fence.sessionID == loaded?.sessionID,
                      fence.operationID == operation.id, fence.cell == step.cell,
                      fence.target == step.target, sameBoot(fence.bootID, operation.bootID) else { return false }
            }
        }
        return true
    }

    /// Never dispatches mutations. A later boot permits observations and releases
    /// already-original cells; it does not replay an interrupted request.
    private func reconcileAdmitted() async throws {
        try store.acquireLock()
        var receiptPending = false
        let loaded: RecoveryJournal?
        do { loaded = try store.loadJournal() }
        catch RecoveryEvidenceError.receiptRequired(let resolved) { loaded = resolved; receiptPending = true }
        journal = loaded
        try checkLegacy(loaded)
        let boot = try currentBoot()
        let fence = try store.loadFence()
        executionUncertain = try !isQuiescent(loaded, fence: fence, boot: boot)
        if !executionUncertain { uncertainBoot = nil }
        let capture = try await transport.capture()
        updateAvailability(capture)
        conflicts = []
        if executionUncertain {
            publish(.recoveryRequired("Execution is uncertain on this boot. Retry can observe settings, but cannot write, release ownership or prove restoration. Keep the evidence; a verified later boot permits read-only reconciliation."))
            return
        }
        guard var current = loaded else { publish(.off); return }
        if current.resolvedAt != nil {
            if receiptPending {
                // Receipt retry verifies every final released observation, including
                // explicit Keep Current, rather than inventing a restored outcome.
                guard current.cells.allSatisfy({ $0.observed != nil && capture.value(for: $0.cell) == $0.observed }) else {
                    throw invalid("The final receipt is incomplete and settings changed. Preserve the evidence for recovery assistance.")
                }
                try store.commitJournal(current)
                try store.saveResolvedReceipt(current)
            }
            publish(.off)
            return
        }
        if current.operation?.steps.contains(where: { $0.phase == .intended || $0.phase == .uncertain }) == true {
            // Completion/boot establishes quiescence, not the missing write receipt.
            // An observed target without lastVerified remains an explicit conflict.
            current.operation = nil
        }
        for index in current.cells.indices where current.cells[index].owned {
            let observed = capture.value(for: current.cells[index].cell)
            current.cells[index].observed = observed
            if observed == current.cells[index].original {
                current.cells[index].owned = false
            } else if observed == nil || observed != current.cells[index].lastVerified {
                conflicts.append(RecoveryConflict(cell: current.cells[index].cell, original: current.cells[index].original,
                    current: observed, lastVerified: current.cells[index].lastVerified))
            }
        }
        if current != loaded { try commit(current) }
        if !current.cells.contains(where: \.owned) {
            try finishResolved()
        } else if !conflicts.isEmpty {
            publish(.recoveryRequired("Some settings differ from the last verified Benzo values. Choose Keep Current, Restore Recorded Original, or defer and keep the evidence."))
        } else {
            let targets = try targetValues(current.selectedSettings.compactMap(SleepSetting.init(rawValue:)), profiles: current.profiles)
            let applied = current.operation.map { operation in
                operation.kind == .apply && operation.steps.allSatisfy {
                    $0.phase == .completed && $0.status == 0 && $0.readback == $0.target
                }
            } ?? false
            if applied && targets.allSatisfy({ capture.value(for: $0.cell) == $0.value }) {
                publish(.activeVerified(now()))
            } else {
                publish(.recoveryRequired("The frozen session is only partly applied or restored. Restore the remaining owned settings before starting again."))
            }
        }
    }

    private func targetValues(_ settings: [SleepSetting], profiles: [PowerProfile]) throws -> [CellValue] {
        var targets: [ManagedCell: Int] = [:]
        for profile in profiles {
            for setting in settings {
                for (name, text) in setting.pmsetCommands {
                    guard let key = ManagedKey(rawValue: name), let value = Int(text), key.isValid(value) else {
                        throw invalid("The selected setting has an unsupported target.")
                    }
                    targets[ManagedCell(profile: profile, key: key)] = value
                }
            }
        }
        return targets.map { CellValue(cell: $0.key, value: $0.value) }.sorted { $0.cell < $1.cell }
    }

    private func updateAvailability(_ capture: ProfileSnapshot) {
        unavailable = [:]
        for setting in SleepSetting.allCases {
            for profile in capture.profiles {
                let missing = setting.pmsetKeys.filter { name in
                    guard let key = ManagedKey(rawValue: name) else { return true }
                    return capture.value(for: ManagedCell(profile: profile, key: key)) == nil
                }
                if !missing.isEmpty {
                    unavailable[setting] = "Unavailable: \(profile.title) does not report \(missing.joined(separator: ", "))."
                    break
                }
            }
        }
    }

    private func commit(_ updated: RecoveryJournal) throws {
        var next = updated
        next.revision += 1
        try store.commitJournal(next)
        journal = next
    }

    private func install(_ plan: RecoveryOperation) throws {
        guard var current = journal, current.resolvedAt == nil, !executionUncertain else {
            throw invalid("No quiescent recovery session is available.")
        }
        current.operation = plan
        try commit(current)
    }

    private func execute(_ plan: RecoveryOperation) async throws {
        for index in plan.steps.indices {
            let step = plan.steps[index]
            let observed = try await transport.capture()
            guard observed.value(for: step.cell) == step.precondition else {
                throw invalid("A setting changed before its write. The remaining plan was stopped.")
            }
            guard var current = journal, current.operation?.id == plan.id,
                  sameBoot(try currentBoot(), plan.bootID) else {
                throw invalid("Operation identity changed before dispatch.")
            }
            current.operation!.steps[index].phase = .intended
            // Covers intent persistence failure and the pre-child-identity gap.
            uncertainBoot = plan.bootID
            executionUncertain = true
            try commit(current)
            var fence = ExecutionFence(uid: uid, hostID: hostID, bootID: plan.bootID,
                incarnationID: incarnationID, sessionID: current.sessionID, operationID: plan.id,
                cell: step.cell, target: step.target, completed: false)
            try store.commitFence(fence)
            let result = await transport.write(cell: step.cell, value: step.target, operationID: plan.id)
            switch result {
            case .uncertain(let message):
                if var uncertain = journal {
                    uncertain.operation!.steps[index].phase = .uncertain
                    // Best effort observations never clear the execution fence.
                    if let observed = try? await transport.capture(),
                       let cellIndex = uncertain.cells.firstIndex(where: { $0.cell == step.cell }) {
                        uncertain.cells[cellIndex].observed = observed.value(for: step.cell)
                    }
                    try? commit(uncertain)
                }
                throw invalid(message)
            case .completed(let status):
                guard (0...255).contains(status) else { throw invalid("Invalid execution status; completion remains unknown.") }
                fence.completed = true
                try store.commitFence(fence)
                uncertainBoot = nil
                executionUncertain = false
                let readback = try await transport.capture()
                guard var completed = journal,
                      let cellIndex = completed.cells.firstIndex(where: { $0.cell == step.cell }) else {
                    throw invalid("Recovery evidence is unavailable after the request.")
                }
                let value = readback.value(for: step.cell)
                completed.operation!.steps[index].phase = .completed
                completed.operation!.steps[index].status = status
                completed.operation!.steps[index].readback = value
                completed.cells[cellIndex].observed = value
                if value == step.target { completed.cells[cellIndex].lastVerified = value }
                try commit(completed)
                guard status == 0, value == step.target else {
                    throw invalid("The setting request failed or its readback did not match. Recovery evidence was retained.")
                }
            }
        }
    }

    private func recoverFailedOperation(_ failed: RecoveryOperation, cause: Error) async {
        guard !executionUncertain else { fail(cause); return }
        do {
            let capture = try await transport.capture()
            guard let current = journal else { throw cause }
            // Compensation retains ownership: reconciliation may already have
            // released restored cells before another cell's conflict was reported.
            let attempted = current.operation?.id == failed.id ? current.operation!.steps : []
            let compensation = attempted.reversed().compactMap { step -> RecoveryStep? in
                guard step.phase == .completed, step.readback == step.target,
                      capture.value(for: step.cell) == step.target,
                      current.cells.first(where: { $0.cell == step.cell && $0.owned })?.lastVerified == step.target else { return nil }
                return RecoveryStep(cell: step.cell, precondition: step.target, target: step.precondition)
            }
            if !compensation.isEmpty {
                let plan = RecoveryOperation(id: UUID(), bootID: try currentBoot(), kind: .compensate, preState: capture.values.filter { current.profiles.contains($0.cell.profile) }, steps: compensation)
                try install(plan)
                try await execute(plan)
            }
            try await reconcileAdmitted()
            // Even a successful rollback must not turn a failed Quit into success.
            publish(.recoveryRequired(cause.localizedDescription + " Review recovery before retrying."))
        } catch { fail(error) }
    }

    private func finishResolved() throws {
        guard var current = journal, !executionUncertain, !current.cells.contains(where: \.owned) else {
            throw invalid("Recovery ownership or execution remains unresolved.")
        }
        current.operation = nil
        current.resolvedAt = now()
        try commit(current)
        guard let resolved = journal else { throw invalid("Resolved evidence is unavailable.") }
        try store.saveResolvedReceipt(resolved)
        conflicts = []
        publish(.off)
    }
}
