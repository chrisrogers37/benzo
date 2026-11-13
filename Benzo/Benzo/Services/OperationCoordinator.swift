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
    private var uncertainCommandToken: PowerCommandToken?
    /// A lost ACK leaves execution settled locally, but the root receipt slot
    /// must be released before another write or compensation can be admitted.
    private var acknowledgementPending = false

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
        guard !admitted, !quitRequested, state == .off, !executionUncertain, !acknowledgementPending else { return false }
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
            if !fence.completed && (fence.commandRequest != nil || sameBoot(fence.bootID, boot)) { return false }
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
        var fence = try store.loadFence()
        if let commandFence = fence, commandFence.commandRequest != nil {
            if !commandFence.completed { executionUncertain = true }
            fence = try await reconcileCommandFence(commandFence, boot: boot)
        }
        // Receipt recovery may have replaced the planned/intended local step.
        let reconciled = journal
        executionUncertain = try !isQuiescent(reconciled, fence: fence, boot: boot)
        if !executionUncertain { uncertainBoot = nil; uncertainCommandToken = nil }
        let capture = try await transport.capture()
        updateAvailability(capture)
        conflicts = []
        if executionUncertain {
            publish(.recoveryRequired("Execution is uncertain on this boot. Retry can observe settings, but cannot write, release ownership or prove restoration. Keep the evidence; a verified later boot permits read-only reconciliation."))
            return
        }
        guard var current = reconciled else { publish(.off); return }
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
        if current != reconciled { try commit(current) }
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
            try await transport.preflightWrite()
            if let request = try await transport.prepareWrite(cell: step.cell, value: step.target,
                expectedValue: step.precondition, operationID: plan.id, bootID: plan.bootID) {
                try await executePrepared(request, step: step, index: index, plan: plan, current: current)
                continue
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
            let result = await transport.write(cell: step.cell, value: step.target, expectedValue: step.precondition,
                                               operationID: plan.id, bootID: plan.bootID)
            switch result {
            case .notExecuted(let message):
                // Only an authenticated helper rejection before dispatch establishes
                // this outcome. A timeout/disconnection must never take this path.
                fence.completed = true
                try store.commitFence(fence)
                guard var rejected = journal else { throw invalid("Recovery evidence is unavailable.") }
                rejected.operation!.steps[index].phase = .notExecuted
                try commit(rejected)
                uncertainBoot = nil
                executionUncertain = false
                throw invalid(message)
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

    private func executePrepared(_ request: PowerCommandRequest, step: RecoveryStep, index: Int,
                                 plan: RecoveryOperation, current: RecoveryJournal) async throws {
        try request.validate()
        guard request.operationID == plan.id, request.cell == step.cell,
              request.expectedValue == step.precondition, request.target == step.target,
              request.bootID == UUID(uuidString: plan.bootID),
              sameBoot(try currentBoot(), plan.bootID) else {
            throw invalid("The prepared power request does not match the frozen recovery step.")
        }
        let fence = ExecutionFence(uid: uid, hostID: hostID, bootID: plan.bootID,
            incarnationID: incarnationID, sessionID: current.sessionID, operationID: plan.id,
            cell: step.cell, target: step.target, completed: false, commandRequest: request)
        uncertainBoot = plan.bootID
        uncertainCommandToken = request.token
        executionUncertain = true
        // The already-persisted plan binds this complete token even if the GUI
        // dies before its intended-step update or before invoking the tool.
        try store.commitFence(fence)
        var intended = current
        intended.operation!.steps[index].phase = .intended
        try commit(intended)
        let outcome = await transport.writePrepared(request)
        switch outcome {
        case .uncertain(let reason):
            if var uncertain = journal, uncertain.operation?.id == plan.id {
                uncertain.operation!.steps[index].phase = .uncertain
                try? commit(uncertain)
            }
            throw invalid(reason)
        case .notExecuted(let reason):
            _ = try await persistCommandTerminal(outcome, fence: fence, index: index)
            throw invalid(reason)
        case .completed(let status):
            let value = try await persistCommandTerminal(outcome, fence: fence, index: index)
            guard status == 0, value == step.target else {
                throw invalid("The setting request failed or its readback did not match. Recovery evidence was retained.")
            }
        }
    }

    /// Inspect the full saved tuple before quiescence. Status/seal is read-only
    /// with respect to settings, and an absent receipt never establishes no-spawn.
    private func reconcileCommandFence(_ original: ExecutionFence, boot: String) async throws -> ExecutionFence {
        try original.validate(uid: uid, hostID: hostID)
        guard let request = original.commandRequest else { return original }
        guard let current = journal, current.sessionID == original.sessionID else {
            // A completed fence may remain after a new session's plan was saved
            // but before its first fence. It cannot supply proof for that session.
            guard original.completed else { throw invalid("The saved power request has no matching recovery session.") }
            return original
        }
        guard current.cells.contains(where: { $0.cell == original.cell }) else {
            throw invalid("The saved power request is outside the captured recovery cells.")
        }
        let index = try boundStepIndex(original, in: current)
        let localTerminal = index.map {
            current.operation!.steps[$0].phase == .completed || current.operation!.steps[$0].phase == .notExecuted
        } ?? original.completed
        let failedLocalCommit = uncertainCommandToken == request.token
        if original.completed, localTerminal, !failedLocalCommit {
            // Includes an already-resolved journal or an operation cleared by
            // prior read-only reconciliation. ACK never renews completion proof.
            return try await acknowledgeCommand(original)
        }

        guard let resolution = await transport.reconcileWrite(request) else {
            uncertainBoot = boot
            uncertainCommandToken = request.token
            executionUncertain = true
            return original
        }
        switch resolution {
        case .terminal(let outcome):
            if case .uncertain = outcome {
                uncertainBoot = boot; uncertainCommandToken = request.token; executionUncertain = true
                return original
            }
            if let index {
                _ = try await persistCommandTerminal(outcome, fence: original, index: index)
            } else {
                // Only a completed fence can reach a cleared operation. A
                // successful fresh durability barrier settles an in-process
                // failed commit; never fabricate a replacement journal step.
                guard original.completed else { throw invalid("Terminal proof has no matching local operation.") }
                try commit(current)
                try store.commitVerifiedCommandFence(original)
                clearCommandUncertainty(request)
                _ = try await acknowledgeCommand(original)
            }
        case .stoppedOnLaterBoot:
            guard request.bootID != UUID(uuidString: boot) else {
                throw invalid("The power request has not stopped on a verified later boot.")
            }
            uncertainBoot = boot
            uncertainCommandToken = request.token
            executionUncertain = true
            var stopped = original
            stopped.completed = true
            // Complete the fence first here: clearing the operation first would
            // leave an incomplete token with no binding after a GUI crash.
            try store.commitVerifiedCommandFence(stopped)
            var reconciled = current
            if reconciled.operation?.id == original.operationID { reconciled.operation = nil }
            try commit(reconciled)
            clearCommandUncertainty(request)
            _ = try await acknowledgeCommand(stopped)
        }
        var completed = original
        completed.completed = true
        completed.commandAcknowledged = true
        return completed
    }

    private func boundStepIndex(_ fence: ExecutionFence, in current: RecoveryJournal) throws -> Int? {
        guard let request = fence.commandRequest else { throw invalid("The saved power request is missing.") }
        guard let operation = current.operation, operation.id == fence.operationID else {
            guard fence.completed else { throw invalid("The saved power request has no matching recovery operation.") }
            return nil
        }
        guard sameBoot(operation.bootID, fence.bootID),
              let index = operation.steps.firstIndex(where: { $0.cell == fence.cell }),
              operation.steps[index].precondition == request.expectedValue,
              operation.steps[index].target == request.target else {
            throw invalid("The saved power request does not match its recovery step and precondition.")
        }
        return index
    }

    /// A retained root receipt is acknowledged only after both local records
    /// have crossed successful durability barriers, including readback evidence.
    private func persistCommandTerminal(_ outcome: RecoveryWriteOutcome, fence: ExecutionFence,
                                        index: Int) async throws -> Int? {
        guard let request = fence.commandRequest, var current = journal,
              current.sessionID == fence.sessionID,
              try boundStepIndex(fence, in: current) == index else {
            throw invalid("Terminal command proof has no matching local recovery step.")
        }
        uncertainBoot = try currentBoot()
        uncertainCommandToken = request.token
        executionUncertain = true
        var value: Int?
        switch outcome {
        case .completed(let status):
            guard (0...255).contains(status) else { throw invalid("Invalid terminal command status.") }
            let capture = try await transport.capture()
            guard sameBoot(try currentBoot(), uncertainBoot!),
                  let cellIndex = current.cells.firstIndex(where: { $0.cell == request.cell }) else {
                throw invalid("Recovery identity changed during command readback.")
            }
            value = capture.value(for: request.cell)
            current.operation!.steps[index].phase = .completed
            current.operation!.steps[index].status = status
            current.operation!.steps[index].readback = value
            current.cells[cellIndex].observed = value
            if value == request.target { current.cells[cellIndex].lastVerified = value }
        case .notExecuted:
            current.operation!.steps[index].phase = .notExecuted
            current.operation!.steps[index].status = nil
            current.operation!.steps[index].readback = nil
        case .uncertain:
            throw invalid("Uncertain execution cannot become a terminal local receipt.")
        }
        try commit(current)
        var completed = fence
        completed.completed = true
        try store.commitVerifiedCommandFence(completed)
        clearCommandUncertainty(request)
        _ = try await acknowledgeCommand(completed)
        return value
    }

    private func clearCommandUncertainty(_ request: PowerCommandRequest) {
        guard uncertainCommandToken == nil || uncertainCommandToken == request.token else { return }
        uncertainBoot = nil
        uncertainCommandToken = nil
        executionUncertain = false
    }

    private func acknowledgeCommand(_ fence: ExecutionFence) async throws -> ExecutionFence {
        guard let request = fence.commandRequest, fence.completed else {
            throw invalid("Only a durably completed command fence may be acknowledged.")
        }
        if fence.commandAcknowledged == true, !acknowledgementPending { return fence }
        acknowledgementPending = true
        try await transport.acknowledgeWrite(request)
        var acknowledged = fence
        acknowledged.commandAcknowledged = true
        try store.commitFence(acknowledged)
        acknowledgementPending = false
        return acknowledged
    }

    private func recoverFailedOperation(_ failed: RecoveryOperation, cause: Error) async {
        guard !executionUncertain, !acknowledgementPending else { fail(cause); return }
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
