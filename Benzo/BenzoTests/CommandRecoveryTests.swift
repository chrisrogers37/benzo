import Foundation
import XCTest
import Darwin

private let commandRecoveryHost = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"
private let commandRecoveryBoot = UUID(uuidString: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB")!
private let commandRecoveryOwner = PowerCommandOwner(uid: 501, generatedUID: UUID(uuidString: "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC")!)
private let commandRecoveryNap = ManagedCell(profile: .ac, key: .powernap)
private let commandRecoveryWake = ManagedCell(profile: .ac, key: .womp)

private final class CommandRecoveryLocalStore: RecoveryStoring {
    var journal: RecoveryJournal?
    var fence: ExecutionFence?
    var receipt: RecoveryJournal?
    var failIntendedJournal = false
    var failTerminalJournal = false
    var failTerminalAfterPublication = false
    var failInitialFence = false
    var failCompletedFence = false
    var failCompletedAfterPublication = false
    var failAckMarker = false
    var failAckMarkerAfterPublication = false
    var events: [String] = []
    func acquireLock() throws {}
    func loadJournal() throws -> RecoveryJournal? {
        try journal?.validate(uid: 501, hostID: commandRecoveryHost)
        return journal
    }
    func commitJournal(_ value: RecoveryJournal) throws {
        try value.validate(uid: 501, hostID: commandRecoveryHost)
        let intended = value.operation?.steps.contains(where: { $0.phase == .intended }) == true
        let terminal = value.operation?.steps.contains(where: { $0.phase == .completed || $0.phase == .notExecuted }) == true
        if (intended && failIntendedJournal) || (terminal && failTerminalJournal) {
            throw RecoveryEvidenceError.invalid("Injected local journal durability failure")
        }
        journal = value
        events.append(intended ? "journal-intended" : (terminal ? "journal-terminal" : "journal"))
        if terminal && failTerminalAfterPublication { throw RecoveryEvidenceError.invalid("Injected post-publication journal failure") }
    }
    func loadFence() throws -> ExecutionFence? { fence }
    func commitFence(_ value: ExecutionFence) throws {
        try value.validate(uid: 501, hostID: commandRecoveryHost)
        if (!value.completed && failInitialFence) || (value.completed && failCompletedFence) {
            throw RecoveryEvidenceError.invalid("Injected local fence durability failure")
        }
        if value.commandAcknowledged == true, failAckMarker { throw RecoveryEvidenceError.invalid("Injected ACK marker failure") }
        fence = value
        events.append(value.commandAcknowledged == true ? "fence-ack" : (value.completed ? "fence-terminal" : "fence-token"))
        if value.completed && failCompletedAfterPublication { throw RecoveryEvidenceError.invalid("Injected post-publication fence failure") }
        if value.commandAcknowledged == true, failAckMarkerAfterPublication { throw RecoveryEvidenceError.invalid("Injected post-publication ACK marker failure") }
    }
    func saveResolvedReceipt(_ value: RecoveryJournal) throws { receipt = value; events.append("resolved") }
    func loadLegacyEvidence() throws -> Data? { nil }
}

private final class CommandRecoveryAuthority: PowerCommandStoring {
    var state = try! PowerCommandState.initial(owner: commandRecoveryOwner)
    func load() throws -> PowerCommandState { state }
    func commit(_ next: PowerCommandState) throws { try next.validateTransition(from: state); state = next }
}

/// Connects the real command engine to the real coordinator through in-memory
/// account, boot, capture and execution boundaries. No process adapter is used.
@MainActor
private final class CommandRecoveryTransport: RecoveryCommanding {
    let local: CommandRecoveryLocalStore
    let authority = CommandRecoveryAuthority()
    var boot = commandRecoveryBoot
    var values: [ManagedCell: Int] = [commandRecoveryNap: 1, commandRecoveryWake: 1]
    var executions: [CellValue] = []
    var commandOutcome: PowerCommandExecution = .completed(exitStatus: 0)
    var mutateOnExecution = true
    var dropBeforeDispatch = false
    var dropAfterDispatch = false
    var failAckBeforeDelivery = false
    var failAckAfterDelivery = false
    var failReadbackAfterExecution = false
    var unavailable = false
    var ackCalls = 0
    var reconcileCalls = 0
    var legacyCalls = 0
    var beforeAck: (() -> Void)?
    lazy var engine = PowerCommandEngine(store: authority, bootID: { self.boot }, capture: { cell in self.values[cell] },
        execute: { cell, value in
            self.local.events.append("execute")
            self.executions.append(CellValue(cell: cell, value: value))
            if self.mutateOnExecution { self.values[cell] = value }
            return self.commandOutcome
        })

    init(local: CommandRecoveryLocalStore) { self.local = local }
    func capture() async throws -> ProfileSnapshot {
        if failReadbackAfterExecution, !executions.isEmpty { throw RecoveryEvidenceError.invalid("Injected lost readback") }
        let raw = "AC Power:\n" + values.keys.sorted().map { " \($0.key.rawValue) \(values[$0]!)" }.joined(separator: "\n")
        return try ProfileSnapshot(parsing: raw)
    }
    func preflightWrite() async throws {
        if unavailable { throw RecoveryEvidenceError.invalid("The command tool was removed or disconnected") }
    }
    func prepareWrite(cell: ManagedCell, value: Int, expectedValue: Int,
                      operationID: UUID, bootID: String) async throws -> PowerCommandRequest? {
        try await preflightWrite()
        let state = authority.state
        guard state.pending == nil, state.highWaterMark < UInt64.max, let boot = UUID(uuidString: bootID) else {
            throw RecoveryEvidenceError.invalid("The command receipt slot is occupied")
        }
        return PowerCommandRequest(grantEpoch: state.grantEpoch, sequence: state.highWaterMark + 1,
            requestID: UUID(), operationID: operationID, bootID: boot, profile: cell.profile, key: cell.key,
            expectedValue: expectedValue, target: value)
    }
    func writePrepared(_ request: PowerCommandRequest) async -> RecoveryWriteOutcome {
        local.events.append("dispatch")
        guard !dropBeforeDispatch else { return .uncertain("GUI transport ended before delivery") }
        let result = await engine.handle(.write(request), caller: commandRecoveryOwner)
        guard !dropAfterDispatch else { return .uncertain("GUI reply was lost after root execution") }
        return (try? result.recoveryOutcome(for: request)) ?? .uncertain("Invalid fixture result")
    }
    func reconcileWrite(_ request: PowerCommandRequest) async -> RecoveryFenceResolution? {
        reconcileCalls += 1
        if unavailable { return nil }
        let status = await engine.handle(.status(request.token), caller: commandRecoveryOwner)
        if let result = try? status.recoveryResolution(for: request) { return result }
        let seal = await engine.handle(.seal(request), caller: commandRecoveryOwner)
        return try? seal.recoveryResolution(for: request)
    }
    func acknowledgeWrite(_ request: PowerCommandRequest) async throws {
        ackCalls += 1
        local.events.append("ack")
        beforeAck?()
        if unavailable { throw RecoveryEvidenceError.invalid("The command tool was removed or disconnected") }
        if failAckBeforeDelivery { throw RecoveryEvidenceError.invalid("Injected lost ACK before delivery") }
        let reply = await engine.handle(.ack(request.token), caller: commandRecoveryOwner)
        guard reply.outcome == .acknowledged else { throw RecoveryEvidenceError.invalid("Fixture ACK rejected") }
        if failAckAfterDelivery { throw RecoveryEvidenceError.invalid("Injected lost ACK reply") }
    }
    func write(cell: ManagedCell, value: Int, expectedValue: Int, operationID: UUID, bootID: String) async -> RecoveryWriteOutcome {
        legacyCalls += 1
        return .uncertain("The command fixture must use its persisted tuple")
    }
}

@MainActor
final class CommandRecoveryTests: XCTestCase {
    private func coordinator(_ store: CommandRecoveryLocalStore, _ transport: CommandRecoveryTransport) -> OperationCoordinator {
        OperationCoordinator(store: store, transport: transport, uid: 501, hostID: commandRecoveryHost,
            bootID: { transport.boot.uuidString }, now: { Date(timeIntervalSince1970: 1000) },
            legacyActive: { false }, legacyRule: { .noLegacyRule })
    }

    func testUnavailableTypedPreparationNeverPersistsIntentOrDispatches() async {
        let store = CommandRecoveryLocalStore()
        let transport = CommandRecoveryTransport(local: store)
        transport.unavailable = true
        let subject = coordinator(store, transport)
        await subject.apply(settings: [.disablePowerNap])
        XCTAssertTrue(transport.executions.isEmpty)
        XCTAssertNil(store.fence)
        XCTAssertNil(transport.authority.state.pending)
        XCTAssertFalse(subject.executionUncertain)
        XCTAssertFalse(subject.state.isActive)
    }

    private func exerciseRealJournal(lostReply: Bool) async throws {
        let directory = URL(fileURLWithPath: "/private/tmp/benzo-command-recovery-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DurableJournal(directory: directory, uid: getuid(), hostID: commandRecoveryHost)
        let transport = CommandRecoveryTransport(local: CommandRecoveryLocalStore())
        func makeCoordinator() -> OperationCoordinator {
            OperationCoordinator(store: store, transport: transport, uid: getuid(), hostID: commandRecoveryHost,
                bootID: { transport.boot.uuidString }, now: { Date(timeIntervalSince1970: 1000) },
                legacyActive: { false }, legacyRule: { .noLegacyRule })
        }
        for _ in 0..<2 {
            transport.dropAfterDispatch = lostReply
            let subject = makeCoordinator()
            await subject.apply(settings: [.disablePowerNap])
            if lostReply {
                XCTAssertTrue(subject.executionUncertain)
                XCTAssertNotNil(transport.authority.state.pending)
            } else { XCTAssertTrue(subject.state.isActive, "\(subject.state)") }
            transport.dropAfterDispatch = false
            let relaunched = makeCoordinator()
            await relaunched.reconcile()
            XCTAssertTrue(relaunched.state.isActive, "\(relaunched.state)")
            XCTAssertEqual(try store.loadFence()?.commandAcknowledged, true)
            XCTAssertNil(transport.authority.state.pending)
            await relaunched.restore()
            XCTAssertEqual(relaunched.state, .off)
            XCTAssertNotNil(try store.loadJournal()?.resolvedAt)
            XCTAssertEqual(try store.loadFence()?.commandAcknowledged, true)
            XCTAssertNil(transport.authority.state.pending)
        }
        XCTAssertEqual(transport.executions.map(\.value), [0, 1, 0, 1])
    }

    func testRealDurableJournalAcceptsCommandAdmissionCompletionAckAndNextSession() async throws {
        try await exerciseRealJournal(lostReply: false)
    }

    func testRealDurableJournalResolvesLostCommandReplyWithoutReboot() async throws {
        try await exerciseRealJournal(lostReply: true)
    }

    func testRealDurableJournalPersistsExplicitLaterBootReconciliationWithoutAdoptingTarget() async throws {
        let directory = URL(fileURLWithPath: "/private/tmp/benzo-command-recovery-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DurableJournal(directory: directory, uid: getuid(), hostID: commandRecoveryHost)
        let transport = CommandRecoveryTransport(local: CommandRecoveryLocalStore())
        transport.commandOutcome = .uncertain(reason: "Injected lost child terminal status")
        func makeCoordinator() -> OperationCoordinator {
            OperationCoordinator(store: store, transport: transport, uid: getuid(), hostID: commandRecoveryHost,
                bootID: { transport.boot.uuidString }, now: { Date(timeIntervalSince1970: 1000) },
                legacyActive: { false }, legacyRule: { .noLegacyRule })
        }
        await makeCoordinator().apply(settings: [.disablePowerNap])
        transport.boot = UUID()
        let relaunched = makeCoordinator()
        await relaunched.reconcile()
        XCTAssertFalse(relaunched.executionUncertain, "\(relaunched.state)")
        XCTAssertEqual(relaunched.conflicts.map(\.cell), [commandRecoveryNap])
        XCTAssertEqual(try store.loadJournal()?.cells.first?.original, 1)
        XCTAssertNil(try store.loadJournal()?.cells.first?.lastVerified)
        XCTAssertNil(try store.loadJournal()?.operation)
        XCTAssertEqual(try store.loadFence()?.commandAcknowledged, true)
        XCTAssertNil(transport.authority.state.pending)
        XCTAssertEqual(transport.executions.count, 1)
        await relaunched.resolveConflict(commandRecoveryNap, choice: .keepCurrent)
        XCTAssertEqual(relaunched.state, .off)
        XCTAssertEqual(transport.executions.count, 1)
    }

    func testRealDurableCompletionMarkerRequiresFreshRootProofBeforeSameBootRepair() async throws {
        let directory = URL(fileURLWithPath: "/private/tmp/benzo-command-recovery-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var failCompletion = true
        let store = DurableJournal(directory: directory, uid: getuid(), hostID: commandRecoveryHost,
            beforeBoundary: { boundary in
                if failCompletion, boundary == .completionMarkerRemove {
                    failCompletion = false
                    throw RecoveryEvidenceError.invalid("Injected interrupted completion finalization")
                }
            })
        let transport = CommandRecoveryTransport(local: CommandRecoveryLocalStore())
        func makeCoordinator() -> OperationCoordinator {
            OperationCoordinator(store: store, transport: transport, uid: getuid(), hostID: commandRecoveryHost,
                bootID: { transport.boot.uuidString }, now: { Date(timeIntervalSince1970: 1000) },
                legacyActive: { false }, legacyRule: { .noLegacyRule })
        }
        let subject = makeCoordinator()
        await subject.apply(settings: [.disablePowerNap])
        XCTAssertTrue(subject.executionUncertain)
        XCTAssertEqual(transport.executions.count, 1)
        XCTAssertEqual(transport.ackCalls, 0)
        XCTAssertEqual(try store.loadFence()?.completed, false)
        var unverified = try XCTUnwrap(store.loadFence())
        unverified.completed = true
        XCTAssertThrowsError(try store.commitFence(unverified), "Ordinary storage entry must preserve same-boot uncertainty")
        let relaunched = makeCoordinator()
        await relaunched.reconcile()
        XCTAssertTrue(relaunched.state.isActive, "\(relaunched.state)")
        XCTAssertFalse(relaunched.executionUncertain)
        XCTAssertEqual(try store.loadFence()?.commandAcknowledged, true)
        XCTAssertEqual(transport.executions.count, 1)
        XCTAssertNil(transport.authority.state.pending)
    }

    func testApplyOffAndRepeatedSessionUsePersistedRequestsAndReleaseReceiptSlots() async {
        let store = CommandRecoveryLocalStore()
        let wired = CommandRecoveryTransport(local: store)
        let subject = coordinator(store, wired)
        for _ in 0..<2 {
            await subject.apply(settings: [.disablePowerNap, .disableNetworkWake])
            XCTAssertTrue(subject.state.isActive)
            XCTAssertEqual(store.journal?.cells.map(\.original), [1, 1])
            XCTAssertNil(wired.authority.state.pending)
            await subject.restore()
            XCTAssertEqual(subject.state, .off)
            XCTAssertEqual(store.journal, store.receipt)
            XCTAssertNil(wired.authority.state.pending)
        }
        XCTAssertEqual(wired.executions.map(\.value), [0, 0, 1, 1, 0, 0, 1, 1])
        XCTAssertEqual(wired.legacyCalls, 0)
    }

    func testOnThenQuitRestoresCapturedOriginalsUsingCommandTransport() async {
        let store = CommandRecoveryLocalStore()
        let transport = CommandRecoveryTransport(local: store)
        let subject = coordinator(store, transport)
        await subject.apply(settings: [.disablePowerNap])
        XCTAssertTrue(subject.state.isActive)
        let quit = await subject.prepareToQuit()
        XCTAssertTrue(quit)
        XCTAssertEqual(subject.state, .off)
        XCTAssertEqual(transport.executions.map(\.value), [0, 1])
        XCTAssertEqual(transport.values[commandRecoveryNap], 1)
        XCTAssertNil(transport.authority.state.pending)
    }

    func testFullTupleFencePrecedesIntendedJournalAndBothTerminalRecordsPrecedeAck() async {
        let store = CommandRecoveryLocalStore()
        let transport = CommandRecoveryTransport(local: store)
        transport.beforeAck = {
            XCTAssertEqual(store.fence?.completed, true)
            XCTAssertNotNil(store.fence?.commandRequest)
            XCTAssertEqual(store.journal?.operation?.steps.first?.phase, .completed)
            XCTAssertEqual(store.journal?.operation?.steps.first?.readback, 0)
            XCTAssertEqual(store.journal?.cells.first?.lastVerified, 0)
        }
        await coordinator(store, transport).apply(settings: [.disablePowerNap])
        let important = store.events.filter { ["fence-token", "journal-intended", "dispatch", "execute", "journal-terminal", "fence-terminal", "ack"].contains($0) }
        XCTAssertEqual(important, ["fence-token", "journal-intended", "dispatch", "execute", "journal-terminal", "fence-terminal", "ack"])
        XCTAssertEqual(store.fence?.commandAcknowledged, true)
    }

    func testRootExitLostGuiReplyReconcilesWithoutRebootOrReplayThenRestores() async {
        let store = CommandRecoveryLocalStore()
        let transport = CommandRecoveryTransport(local: store)
        transport.dropAfterDispatch = true
        let first = coordinator(store, transport)
        await first.apply(settings: [.disablePowerNap])
        XCTAssertTrue(first.executionUncertain)
        XCTAssertEqual(transport.executions.count, 1)
        XCTAssertEqual(transport.authority.state.pending?.outcome, .completed(exitStatus: 0))
        XCTAssertEqual(transport.ackCalls, 0)
        transport.dropAfterDispatch = false
        let relaunched = coordinator(store, transport)
        await relaunched.reconcile()
        XCTAssertTrue(relaunched.state.isActive)
        XCTAssertFalse(relaunched.executionUncertain)
        XCTAssertEqual(transport.executions.count, 1)
        XCTAssertNil(transport.authority.state.pending)
        await relaunched.restore()
        XCTAssertEqual(relaunched.state, .off)
        XCTAssertEqual(transport.executions.map(\.value), [0, 1])
    }

    func testGuiDeathBeforeWriteSealsTokenAndBarsLateDeliveryAfterAck() async throws {
        let store = CommandRecoveryLocalStore()
        let transport = CommandRecoveryTransport(local: store)
        transport.dropBeforeDispatch = true
        await coordinator(store, transport).apply(settings: [.disablePowerNap])
        let request = try XCTUnwrap(store.fence?.commandRequest)
        XCTAssertEqual(transport.authority.state.highWaterMark, 0)
        let relaunched = coordinator(store, transport)
        await relaunched.reconcile()
        XCTAssertEqual(relaunched.state, .off)
        XCTAssertEqual(transport.authority.state.highWaterMark, 1)
        XCTAssertNil(transport.authority.state.pending)
        transport.dropBeforeDispatch = false
        let late = await transport.writePrepared(request)
        guard case .uncertain = late else { return XCTFail("Retired token must never regenerate completion") }
        XCTAssertTrue(transport.executions.isEmpty)
        XCTAssertEqual(store.journal?.cells.first?.original, 1)
    }

    func testDeathBetweenFenceAndIntendedJournalUsesSavedPlannedStepToSeal() async {
        let store = CommandRecoveryLocalStore()
        let transport = CommandRecoveryTransport(local: store)
        store.failIntendedJournal = true
        await coordinator(store, transport).apply(settings: [.disablePowerNap])
        XCTAssertEqual(store.journal?.operation?.steps.first?.phase, .planned)
        XCTAssertNotNil(store.fence?.commandRequest)
        XCTAssertTrue(transport.executions.isEmpty)
        store.failIntendedJournal = false
        let relaunched = coordinator(store, transport)
        await relaunched.reconcile()
        XCTAssertEqual(relaunched.state, .off)
        XCTAssertTrue(transport.executions.isEmpty)
        XCTAssertEqual(transport.authority.state.highWaterMark, 1)
    }

    func testFailureBeforeFenceCommitNeverDispatchesOrLaundersInProcessUncertainty() async {
        let store = CommandRecoveryLocalStore()
        let transport = CommandRecoveryTransport(local: store)
        store.failInitialFence = true
        let subject = coordinator(store, transport)
        await subject.apply(settings: [.disablePowerNap])
        XCTAssertNil(store.fence)
        XCTAssertEqual(store.journal?.operation?.steps.first?.phase, .planned)
        XCTAssertTrue(transport.executions.isEmpty)
        await subject.reconcile()
        XCTAssertTrue(subject.executionUncertain)
        XCTAssertNotEqual(subject.state, .off)
        XCTAssertNil(store.receipt)
    }

    func testLostAckBeforeAndAfterDeliveryRetriesWithoutReplayOrDowngradingStep() async {
        for beforeDelivery in [true, false] {
            let store = CommandRecoveryLocalStore()
            let transport = CommandRecoveryTransport(local: store)
            transport.failAckBeforeDelivery = beforeDelivery
            transport.failAckAfterDelivery = !beforeDelivery
            let subject = coordinator(store, transport)
            await subject.apply(settings: [.disablePowerNap])
            XCTAssertFalse(subject.executionUncertain)
            XCTAssertEqual(store.fence?.completed, true)
            XCTAssertEqual(store.journal?.operation?.steps.first?.phase, .completed)
            XCTAssertEqual(transport.executions.count, 1)
            XCTAssertEqual(transport.authority.state.pending != nil, beforeDelivery)
            transport.failAckBeforeDelivery = false
            transport.failAckAfterDelivery = false
            let relaunched = coordinator(store, transport)
            await relaunched.reconcile()
            XCTAssertTrue(relaunched.state.isActive)
            XCTAssertEqual(transport.executions.count, 1)
            XCTAssertEqual(transport.reconcileCalls, 0, "Durable local completion only needs idempotent ACK")
            XCTAssertEqual(store.journal?.operation?.steps.first?.status, 0)
            XCTAssertNil(transport.authority.state.pending)
        }
    }

    func testAckRetryAlsoWorksWithResolvedJournalAndClearedOperation() async throws {
        let store = CommandRecoveryLocalStore()
        let transport = CommandRecoveryTransport(local: store)
        let subject = coordinator(store, transport)
        await subject.apply(settings: [.disablePowerNap])
        transport.beforeAck = {
            if transport.executions.count == 2 { transport.failAckBeforeDelivery = true }
        }
        await subject.restore()
        var resolved = try XCTUnwrap(store.journal)
        resolved.cells[0].owned = false
        resolved.operation = nil
        resolved.resolvedAt = Date(timeIntervalSince1970: 1000)
        try store.commitJournal(resolved)
        try store.saveResolvedReceipt(resolved)
        transport.beforeAck = nil
        transport.failAckBeforeDelivery = false
        let relaunched = coordinator(store, transport)
        await relaunched.reconcile()
        XCTAssertEqual(relaunched.state, .off)
        XCTAssertNil(transport.authority.state.pending)
        XCTAssertEqual(transport.executions.map(\.value), [0, 1])
        XCTAssertNil(store.journal?.operation)
    }

    func testSealAfterRootIntentRemainsUncertainEvenWhenReadsMatchOriginal() async {
        let store = CommandRecoveryLocalStore()
        let transport = CommandRecoveryTransport(local: store)
        transport.commandOutcome = .uncertain(reason: "The owned child has no terminal proof")
        transport.mutateOnExecution = false
        await coordinator(store, transport).apply(settings: [.disablePowerNap])
        let relaunched = coordinator(store, transport)
        await relaunched.reconcile()
        await relaunched.restore()
        XCTAssertTrue(relaunched.executionUncertain)
        XCTAssertNotEqual(relaunched.state, .off)
        XCTAssertEqual(transport.authority.state.pending?.outcome, .intent)
        XCTAssertEqual(transport.executions.count, 1)
        XCTAssertEqual(transport.ackCalls, 0)
        XCTAssertEqual(store.journal?.cells.first?.owned, true)
    }

    func testDurablyAcknowledgedResolvedSessionStaysOffAndCanQuitAfterToolRemoval() async {
        let store = CommandRecoveryLocalStore()
        let transport = CommandRecoveryTransport(local: store)
        let subject = coordinator(store, transport)
        await subject.apply(settings: [.disablePowerNap])
        await subject.restore()
        XCTAssertEqual(subject.state, .off)
        XCTAssertEqual(store.fence?.commandAcknowledged, true)
        let ackCalls = transport.ackCalls
        transport.unavailable = true
        let relaunched = coordinator(store, transport)
        await relaunched.reconcile()
        XCTAssertEqual(relaunched.state, .off)
        let mayQuit = await relaunched.prepareToQuit()
        XCTAssertTrue(mayQuit)
        XCTAssertEqual(transport.ackCalls, ackCalls)
        XCTAssertEqual(transport.reconcileCalls, 0)
        XCTAssertEqual(transport.executions.map(\.value), [0, 1])
    }

    func testFailedAckMarkerRetriesAfterRootReceiptGoneWithoutInventingExecutionUncertainty() async {
        for afterPublication in [false, true] {
            let store = CommandRecoveryLocalStore()
            let transport = CommandRecoveryTransport(local: store)
            store.failAckMarker = !afterPublication
            store.failAckMarkerAfterPublication = afterPublication
            let subject = coordinator(store, transport)
            await subject.apply(settings: [.disablePowerNap])
            XCTAssertNil(transport.authority.state.pending)
            XCTAssertFalse(subject.executionUncertain)
            XCTAssertEqual(store.journal?.operation?.steps.first?.phase, .completed)
            XCTAssertEqual(transport.ackCalls, 1)
            await subject.reconcile()
            XCTAssertEqual(transport.ackCalls, 2, "Visible ACK metadata cannot launder its failed durability barrier")
            XCTAssertFalse(subject.state.isActive)
            store.failAckMarker = false
            store.failAckMarkerAfterPublication = false
            await subject.reconcile()
            XCTAssertTrue(subject.state.isActive)
            XCTAssertFalse(subject.executionUncertain)
            XCTAssertEqual(store.fence?.commandAcknowledged, true)
            XCTAssertEqual(transport.executions.count, 1)
        }
    }

    func testLaterBootExplicitReconciliationKeepsTargetUnverifiedAndOriginalImmutable() async {
        let store = CommandRecoveryLocalStore()
        let transport = CommandRecoveryTransport(local: store)
        transport.commandOutcome = .uncertain(reason: "No terminal proof")
        await coordinator(store, transport).apply(settings: [.disablePowerNap])
        transport.boot = UUID()
        let relaunched = coordinator(store, transport)
        await relaunched.reconcile()
        XCTAssertFalse(relaunched.executionUncertain)
        XCTAssertNotEqual(relaunched.state, .off)
        XCTAssertFalse(relaunched.state.isActive)
        XCTAssertEqual(relaunched.conflicts.map(\.cell), [commandRecoveryNap])
        XCTAssertEqual(store.journal?.cells.first?.original, 1)
        XCTAssertNil(store.journal?.cells.first?.lastVerified)
        XCTAssertNil(store.journal?.operation)
        XCTAssertNil(transport.authority.state.pending)
        XCTAssertEqual(transport.executions.count, 1)
    }

    func testLocalTerminalDurabilityFailuresNeverAckOrBecomeOffFromReadback() async {
        for failure in 0..<4 {
            let store = CommandRecoveryLocalStore()
            let transport = CommandRecoveryTransport(local: store)
            store.failTerminalJournal = failure == 0
            store.failCompletedFence = failure == 1
            store.failTerminalAfterPublication = failure == 2
            store.failCompletedAfterPublication = failure == 3
            let subject = coordinator(store, transport)
            await subject.apply(settings: [.disablePowerNap])
            XCTAssertTrue(subject.executionUncertain)
            transport.values[commandRecoveryNap] = 1
            await subject.reconcile()
            XCTAssertTrue(subject.executionUncertain, "Fault \(failure)")
            XCTAssertNotEqual(subject.state, .off)
            XCTAssertEqual(transport.ackCalls, 0)
            XCTAssertNotNil(transport.authority.state.pending)
            XCTAssertNil(store.receipt)
            store.failTerminalJournal = false
            store.failCompletedFence = false
            store.failTerminalAfterPublication = false
            store.failCompletedAfterPublication = false
            await subject.reconcile()
            XCTAssertFalse(subject.executionUncertain)
            XCTAssertEqual(subject.state, .off)
            XCTAssertNil(transport.authority.state.pending)
            XCTAssertEqual(transport.executions.count, 1)
        }
    }

    func testMissingReadbackRetainsRootReceiptUntilLocalReadbackCanBePersisted() async {
        let store = CommandRecoveryLocalStore()
        let transport = CommandRecoveryTransport(local: store)
        transport.failReadbackAfterExecution = true
        let subject = coordinator(store, transport)
        await subject.apply(settings: [.disablePowerNap])
        XCTAssertTrue(subject.executionUncertain)
        XCTAssertEqual(transport.ackCalls, 0)
        XCTAssertNotNil(transport.authority.state.pending)
        XCTAssertNil(store.journal?.cells.first?.lastVerified)
        transport.failReadbackAfterExecution = false
        await subject.reconcile()
        XCTAssertTrue(subject.state.isActive)
        XCTAssertEqual(transport.executions.count, 1)
        XCTAssertNil(transport.authority.state.pending)
    }

    func testMismatchedSavedPreconditionNeverConsumesRootReceipt() async throws {
        let store = CommandRecoveryLocalStore()
        let transport = CommandRecoveryTransport(local: store)
        transport.dropAfterDispatch = true
        await coordinator(store, transport).apply(settings: [.disablePowerNap])
        let fence = try XCTUnwrap(store.fence)
        let original = try XCTUnwrap(fence.commandRequest)
        let wrong = PowerCommandRequest(grantEpoch: original.grantEpoch, sequence: original.sequence,
            requestID: original.requestID, operationID: original.operationID, bootID: original.bootID,
            profile: original.profile, key: original.key, expectedValue: 0, target: original.target)
        store.fence = ExecutionFence(uid: fence.uid, hostID: fence.hostID, bootID: fence.bootID,
            incarnationID: fence.incarnationID, sessionID: fence.sessionID, operationID: fence.operationID,
            cell: fence.cell, target: fence.target, completed: false, commandRequest: wrong)
        let relaunched = coordinator(store, transport)
        await relaunched.reconcile()
        XCTAssertNotEqual(relaunched.state, .off)
        XCTAssertFalse(relaunched.state.isActive)
        XCTAssertEqual(transport.reconcileCalls, 0)
        XCTAssertEqual(transport.ackCalls, 0)
        XCTAssertNotNil(transport.authority.state.pending)
    }

    func testOldSchemaFenceRemainsConservativeOnSameBoot() async throws {
        let store = CommandRecoveryLocalStore()
        let transport = CommandRecoveryTransport(local: store)
        transport.dropBeforeDispatch = true
        await coordinator(store, transport).apply(settings: [.disablePowerNap])
        let fence = try XCTUnwrap(store.fence)
        store.fence = ExecutionFence(uid: fence.uid, hostID: fence.hostID, bootID: fence.bootID,
            incarnationID: fence.incarnationID, sessionID: fence.sessionID, operationID: fence.operationID,
            cell: fence.cell, target: fence.target, completed: false)
        let relaunched = coordinator(store, transport)
        await relaunched.reconcile()
        XCTAssertTrue(relaunched.executionUncertain)
        XCTAssertEqual(transport.reconcileCalls, 0)
        XCTAssertEqual(transport.ackCalls, 0)
        XCTAssertNil(store.receipt)
        XCTAssertTrue(transport.executions.isEmpty)
    }
}
