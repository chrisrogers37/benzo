import Foundation
import XCTest
import Darwin

private let engineHost = "11111111-1111-4111-8111-111111111111"
private let engineBoot = "22222222-2222-4222-8222-222222222222"
private let laterEngineBoot = "33333333-3333-4333-8333-333333333333"

private final class EngineStore: RecoveryStoring {
    var journal: RecoveryJournal?
    var fence: ExecutionFence?
    var receipt: RecoveryJournal?
    var legacy: Data?
    var loadError = false
    var failJournalCommit = false
    var failCompletedFence = false
    var failReceipt = false
    var writes: [RecoveryJournal] = []
    func acquireLock() throws {}
    func loadJournal() throws -> RecoveryJournal? {
        if loadError { throw RecoveryEvidenceError.invalid("Unreadable evidence") }
        if let journal, journal.resolvedAt != nil, receipt != journal { throw RecoveryEvidenceError.receiptRequired(journal) }
        return journal
    }
    func commitJournal(_ journal: RecoveryJournal) throws {
        if failJournalCommit { throw RecoveryEvidenceError.invalid("Injected journal failure") }
        try journal.validate(uid: 501, hostID: engineHost)
        self.journal = journal
        writes.append(journal)
    }
    func loadFence() throws -> ExecutionFence? { fence }
    func commitFence(_ fence: ExecutionFence) throws {
        if fence.completed && failCompletedFence { throw RecoveryEvidenceError.invalid("Injected completion persistence failure") }
        self.fence = fence
    }
    func saveResolvedReceipt(_ journal: RecoveryJournal) throws {
        if failReceipt { throw RecoveryEvidenceError.invalid("Injected receipt failure") }
        receipt = journal
    }
    func loadLegacyEvidence() throws -> Data? { legacy }
}

private final class EngineTransport: RecoveryCommanding {
    var values: [ManagedCell: Int]
    var profiles: [PowerProfile]
    var writes: [CellValue] = []
    var preflightError: Error?
    var captureCount = 0
    var beforeCapture: ((Int) throws -> Void)?
    var onWrite: ((ManagedCell, Int, Int) async -> RecoveryWriteOutcome)?
    init(_ values: [ManagedCell: Int], profiles: [PowerProfile] = [.ac]) {
        self.values = values; self.profiles = profiles
    }
    func capture() async throws -> ProfileSnapshot {
        captureCount += 1
        try beforeCapture?(captureCount)
        let raw = profiles.map { profile in
            profile.title + ":\n" + values.keys.filter { $0.profile == profile }.sorted().map {
                " \($0.key.rawValue) \(values[$0]!)"
            }.joined(separator: "\n")
        }.joined(separator: "\n")
        return try ProfileSnapshot(parsing: raw)
    }
    func preflightWrite() async throws { if let preflightError { throw preflightError } }
    func write(cell: ManagedCell, value: Int, expectedValue: Int, operationID: UUID, bootID: String) async -> RecoveryWriteOutcome {
        writes.append(CellValue(cell: cell, value: value))
        if let onWrite { return await onWrite(cell, value, writes.count) }
        values[cell] = value
        return .completed(status: 0)
    }
}

@MainActor
final class RecoveryEngineTests: XCTestCase {
    private let acNap = ManagedCell(profile: .ac, key: .powernap)
    private let batteryNap = ManagedCell(profile: .battery, key: .powernap)
    private let acWake = ManagedCell(profile: .ac, key: .womp)
    private func engine(_ store: EngineStore, _ transport: EngineTransport,
                        boot: @escaping () throws -> String = { engineBoot }, legacyActive: Bool = false) -> OperationCoordinator {
        OperationCoordinator(store: store, transport: transport, uid: 501, hostID: engineHost,
            bootID: boot, now: { Date(timeIntervalSince1970: 1000) }, legacyActive: { legacyActive }, legacyRule: { .noLegacyRule })
    }

    func testDistinctProfilesOwnOnlyChangedCellsAndRestoreFrozenOriginals() async throws {
        let store = EngineStore(), transport = EngineTransport([acNap: 1, batteryNap: 0], profiles: [.ac, .battery])
        let subject = engine(store, transport)
        await subject.apply(settings: [.disablePowerNap])
        XCTAssertTrue(subject.state.isActive)
        XCTAssertEqual(store.journal?.cells.map(\.cell), [acNap])
        XCTAssertEqual(transport.writes, [CellValue(cell: acNap, value: 0)])
        // A newly appearing profile never joins the frozen session.
        let ups = ManagedCell(profile: .ups, key: .powernap)
        transport.profiles.append(.ups); transport.values[ups] = 1
        await subject.restore()
        XCTAssertEqual(subject.state, .off)
        XCTAssertEqual(transport.writes, [CellValue(cell: acNap, value: 0), CellValue(cell: acNap, value: 1)])
        XCTAssertEqual(transport.values[batteryNap], 0)
        XCTAssertEqual(transport.values[ups], 1)
        XCTAssertEqual(store.journal, store.receipt)
    }

    func testEmptyAndUnsupportedPlansDispatchNothing() async {
        for settings: [SleepSetting] in [[], [.hibernateMode]] {
            let store = EngineStore(), transport = EngineTransport([acNap: 1])
            let subject = engine(store, transport)
            await subject.apply(settings: settings)
            XCTAssertTrue(transport.writes.isEmpty)
            XCTAssertNil(store.journal)
            XCTAssertFalse(subject.state.isActive)
        }
    }

    func testRealDurableStoreAndCoordinatorSupportTwoResolvedSessions() async throws {
        let directory = URL(fileURLWithPath: "/private/tmp/benzo-engine-store-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DurableJournal(directory: directory, uid: getuid(), hostID: engineHost)
        let transport = EngineTransport([acNap: 1, acWake: 1])
        let subject = OperationCoordinator(store: store, transport: transport, uid: getuid(), hostID: engineHost,
            bootID: { engineBoot }, now: { Date() }, legacyActive: { false }, legacyRule: { .noLegacyRule })
        for _ in 0..<2 {
            await subject.apply(settings: [.disablePowerNap, .disableNetworkWake])
            XCTAssertTrue(subject.state.isActive)
            XCTAssertFalse(subject.mayEditSelections())
            await subject.restore()
            XCTAssertEqual(subject.state, .off)
            XCTAssertTrue(subject.mayEditSelections())
            XCTAssertNotNil(try store.loadJournal()?.resolvedAt)
        }
        XCTAssertEqual(transport.writes.count, 8)
        XCTAssertEqual(transport.values[acNap], 1)
        XCTAssertEqual(transport.values[acWake], 1)
    }

    func testLostReadbackRetainsOwnershipAndDoesNotInventVerifiedWrite() async {
        let store = EngineStore(), transport = EngineTransport([acNap: 1])
        var failNextRead = false
        transport.onWrite = { [unowned transport] cell, value, _ in
            transport.values[cell] = value
            failNextRead = true
            return .completed(status: 0)
        }
        transport.beforeCapture = { _ in
            if failNextRead {
                failNextRead = false
                throw RecoveryEvidenceError.invalid("Readback unavailable")
            }
        }
        let subject = engine(store, transport)
        await subject.apply(settings: [.disablePowerNap])
        XCTAssertEqual(transport.writes.count, 1)
        XCTAssertEqual(store.journal?.cells.first?.owned, true)
        XCTAssertNil(store.journal?.cells.first?.lastVerified)
        XCTAssertEqual(subject.conflicts.map(\.cell), [acNap])
        XCTAssertFalse(subject.state.isActive)
    }

    func testPrewritePersistenceFailureDispatchesNothing() async {
        let store = EngineStore(), transport = EngineTransport([acNap: 1])
        store.failJournalCommit = true
        let subject = engine(store, transport)
        await subject.apply(settings: [.disablePowerNap])
        XCTAssertTrue(transport.writes.isEmpty)
        guard case .recoveryRequired = subject.state else { return XCTFail("Persistence failure must be visible") }
    }

    func testNonzeroAfterMutationCompensatesToOperationPreState() async {
        let store = EngineStore(), transport = EngineTransport([acNap: 1, acWake: 1])
        transport.onWrite = { [unowned transport] cell, value, count in
            transport.values[cell] = value
            return .completed(status: count == 2 ? 1 : 0)
        }
        let subject = engine(store, transport)
        await subject.apply(settings: [.disablePowerNap, .disableNetworkWake])
        XCTAssertEqual(transport.writes.map(\.cell), [acNap, acWake, acWake, acNap])
        XCTAssertEqual(transport.writes.map(\.value), [0, 0, 1, 1])
        XCTAssertEqual(transport.values[acNap], 1)
        XCTAssertEqual(transport.values[acWake], 1)
        XCTAssertEqual(store.journal?.cells.map(\.original), [1, 1])
        XCTAssertFalse(subject.state.isActive)
    }

    func testFailedRestoreCompensatesOwnedCellsAndPreservesOriginalsForRetry() async {
        let store = EngineStore(), transport = EngineTransport([acNap: 1, acWake: 1])
        let subject = engine(store, transport)
        await subject.apply(settings: [.disablePowerNap, .disableNetworkWake])
        transport.onWrite = { [unowned transport] cell, value, count in
            transport.values[cell] = value
            return .completed(status: count == 4 ? 1 : 0)
        }

        await subject.restore()
        XCTAssertEqual(transport.writes.map(\.cell), [acNap, acWake, acNap, acWake, acWake, acNap])
        XCTAssertEqual(transport.writes.map(\.value), [0, 0, 1, 1, 0, 0])
        XCTAssertEqual(store.journal?.cells.map(\.original), [1, 1])
        XCTAssertEqual(store.journal?.cells.map(\.lastVerified), [0, 0])
        XCTAssertEqual(store.journal?.cells.map(\.owned), [true, true])
        XCTAssertNil(store.receipt)
        guard case .recoveryRequired = subject.state else { return XCTFail("Failed restore must remain visible") }

        let canQuit = await subject.prepareToQuit()
        XCTAssertTrue(canQuit)
        XCTAssertEqual(transport.writes.map(\.value), [0, 0, 1, 1, 0, 0, 1, 1])
        XCTAssertEqual(transport.values[acNap], 1)
        XCTAssertEqual(transport.values[acWake], 1)
        XCTAssertEqual(subject.state, .off)
        XCTAssertEqual(store.journal, store.receipt)
    }

    func testPostRestoreConflictNeverCompensatesReleasedCells() async {
        let hib = ManagedCell(profile: .ac, key: .hibernatemode)
        let standby = ManagedCell(profile: .ac, key: .standby)
        let auto = ManagedCell(profile: .ac, key: .autopoweroff)
        let store = EngineStore(), transport = EngineTransport([hib: 3, standby: 1, auto: 1])
        let subject = engine(store, transport)
        await subject.apply(settings: [.hibernateMode])
        XCTAssertTrue(subject.state.isActive)

        var readsAfterLastRestore = 0
        transport.beforeCapture = { [unowned transport] _ in
            guard transport.writes.count == 6 else { return }
            readsAfterLastRestore += 1
            if readsAfterLastRestore == 2 {
                // After every restore readback, another tool changes one cell.
                // Reconciliation releases the other cells before reporting this conflict.
                transport.values[hib] = 0
            }
        }
        await subject.restore()
        XCTAssertEqual(subject.conflicts.map(\.cell), [hib])
        XCTAssertEqual(transport.writes.count, 6)
        XCTAssertEqual(transport.values[standby], 1)
        XCTAssertEqual(transport.values[auto], 1)
        XCTAssertEqual(store.journal?.cells.filter(\.owned).map(\.cell), [hib])
        XCTAssertNil(store.receipt)

        await subject.resolveConflict(hib, choice: .keepCurrent)
        XCTAssertEqual(subject.state, .off)
        XCTAssertEqual(transport.writes.count, 6)
        XCTAssertEqual(transport.values[hib], 0)
        XCTAssertEqual(transport.values[standby], 1)
        XCTAssertEqual(transport.values[auto], 1)
        XCTAssertEqual(store.journal, store.receipt)
    }

    func testExitZeroMismatchStopsAndNeverRestoresUnverifiedThirdValue() async {
        let store = EngineStore(), transport = EngineTransport([acNap: 1, acWake: 1])
        transport.onWrite = { _, _, _ in .completed(status: 0) }
        let subject = engine(store, transport)
        await subject.apply(settings: [.disablePowerNap, .disableNetworkWake])
        XCTAssertEqual(transport.writes.count, 1)
        XCTAssertEqual(transport.values[acWake], 1)
        XCTAssertFalse(subject.state.isActive)
    }

    func testUncertainMutationAndSameBootRelaunchCannotReleaseMatchingOriginals() async {
        let store = EngineStore(), transport = EngineTransport([acNap: 1])
        transport.onWrite = { _, _, _ in .uncertain("Lost privileged completion") }
        let subject = engine(store, transport)
        await subject.apply(settings: [.disablePowerNap])
        XCTAssertTrue(subject.executionUncertain)
        let relaunched = engine(store, transport)
        await relaunched.reconcile()
        await relaunched.restore()
        await relaunched.resolveConflict(acNap, choice: .keepCurrent)
        let quit = await relaunched.prepareToQuit()
        XCTAssertFalse(quit)
        XCTAssertTrue(relaunched.executionUncertain)
        XCTAssertEqual(transport.writes.count, 1)
        XCTAssertEqual(store.journal?.cells.first?.owned, true)
        XCTAssertNil(store.receipt)
    }

    func testLaterBootReconcilesOriginalsWithoutReplay() async {
        let store = EngineStore(), transport = EngineTransport([acNap: 1])
        transport.onWrite = { _, _, _ in .uncertain("Unknown") }
        await engine(store, transport).apply(settings: [.disablePowerNap])
        let later = engine(store, transport, boot: { laterEngineBoot })
        await later.reconcile()
        XCTAssertEqual(later.state, .off)
        XCTAssertEqual(transport.writes.count, 1)
        XCTAssertNotNil(store.receipt)
    }

    func testMissingFenceInIntendedJournalBlocksSameBootButAllowsLaterReadOnlyReconcile() async {
        let store = EngineStore(), transport = EngineTransport([acNap: 1])
        transport.onWrite = { _, _, _ in .uncertain("Unknown") }
        await engine(store, transport).apply(settings: [.disablePowerNap])
        store.fence = nil // Journal intent also fences the pre-child-identity gap.
        let same = engine(store, transport)
        await same.reconcile()
        XCTAssertTrue(same.executionUncertain)
        let later = engine(store, transport, boot: { laterEngineBoot })
        await later.reconcile()
        XCTAssertEqual(later.state, .off)
        XCTAssertEqual(transport.writes.count, 1)
    }

    func testFailedCompletionCommitCannotBeClearedByReadback() async {
        let store = EngineStore(), transport = EngineTransport([acNap: 1])
        store.failCompletedFence = true
        let subject = engine(store, transport)
        await subject.apply(settings: [.disablePowerNap])
        transport.values[acNap] = 1
        await subject.reconcile()
        XCTAssertTrue(subject.executionUncertain)
        XCTAssertEqual(store.journal?.cells.first?.owned, true)
        XCTAssertNil(store.receipt)
        XCTAssertEqual(transport.writes.count, 1)
    }

    func testNonzeroCompletedStepCannotBecomeActiveOnRelaunch() async throws {
        let store = EngineStore(), transport = EngineTransport([acNap: 1])
        let subject = engine(store, transport)
        await subject.apply(settings: [.disablePowerNap])
        store.journal!.operation!.steps[0].status = 1 // Crash after failed readback receipt, before compensation.
        let relaunched = engine(store, transport)
        await relaunched.reconcile()
        XCTAssertFalse(relaunched.state.isActive)
        guard case .recoveryRequired = relaunched.state else { return XCTFail("A failed operation must remain visible") }
        XCTAssertEqual(transport.writes.count, 1)
    }

    func testConflictKeepCurrentReleasesOnlyChosenCellAndRestorePreservesIt() async {
        let hib = ManagedCell(profile: .ac, key: .hibernatemode)
        let standby = ManagedCell(profile: .ac, key: .standby)
        let auto = ManagedCell(profile: .ac, key: .autopoweroff)
        let store = EngineStore(), transport = EngineTransport([hib: 3, standby: 1, auto: 1])
        let subject = engine(store, transport)
        await subject.apply(settings: [.hibernateMode])
        transport.values[hib] = 0 // Third value requires a choice, never automatic restore.
        await subject.reconcile()
        XCTAssertEqual(subject.conflicts.map(\.cell), [hib])
        let writesBefore = transport.writes.count
        await subject.resolveConflict(hib, choice: .keepCurrent)
        XCTAssertEqual(transport.writes.count, writesBefore)
        XCTAssertTrue(subject.hasSession)
        await subject.restore()
        XCTAssertEqual(subject.state, .off)
        XCTAssertEqual(transport.values[hib], 0)
        XCTAssertEqual(transport.values[standby], 1)
        XCTAssertEqual(transport.values[auto], 1)
    }

    func testConflictRestoreOriginalRequiresExplicitChoice() async {
        let hib = ManagedCell(profile: .ac, key: .hibernatemode)
        let standby = ManagedCell(profile: .ac, key: .standby)
        let auto = ManagedCell(profile: .ac, key: .autopoweroff)
        let store = EngineStore(), transport = EngineTransport([hib: 3, standby: 0, auto: 0])
        let subject = engine(store, transport)
        await subject.apply(settings: [.hibernateMode])
        transport.values[hib] = 0
        await subject.restore()
        XCTAssertEqual(transport.writes.count, 1)
        await subject.resolveConflict(hib, choice: .restoreOriginal)
        XCTAssertEqual(transport.values[hib], 3)
        XCTAssertEqual(subject.state, .off)
    }

    func testReceiptFailureNeverPublishesOffAndCanRetryReadOnly() async {
        let store = EngineStore(), transport = EngineTransport([acNap: 1])
        let subject = engine(store, transport)
        await subject.apply(settings: [.disablePowerNap])
        store.failReceipt = true
        await subject.restore()
        XCTAssertNotEqual(subject.state, .off)
        XCTAssertEqual(transport.values[acNap], 1)
        let count = transport.writes.count
        store.failReceipt = false
        await subject.reconcile()
        XCTAssertEqual(subject.state, .off)
        XCTAssertEqual(transport.writes.count, count)
    }

    func testCorruptLegacyAndMissingSavedActiveEvidenceNeverBecomeOff() async {
        for scenario in 0..<3 {
            let store = EngineStore(), transport = EngineTransport([acNap: 1])
            store.loadError = scenario == 0
            store.legacy = scenario == 1 ? Data("legacy".utf8) : nil
            let subject = engine(store, transport, legacyActive: scenario == 2)
            await subject.reconcile()
            XCTAssertNotEqual(subject.state, .off)
            XCTAssertFalse(subject.mayEditSelections())
            XCTAssertTrue(transport.writes.isEmpty)
        }
    }

    func testAdmissionSpansAuthorizationAndQuitWaitsThenRestores() async {
        let store = EngineStore(), transport = EngineTransport([acNap: 1])
        var release: CheckedContinuation<Void, Never>?
        transport.onWrite = { [unowned transport] cell, value, count in
            if count == 1 { await withCheckedContinuation { release = $0 } }
            transport.values[cell] = value
            return .completed(status: 0)
        }
        let subject = engine(store, transport)
        let applying = Task { await subject.apply(settings: [.disablePowerNap]) }
        for _ in 0..<10_000 where release == nil { await Task.yield() }
        guard release != nil else { return XCTFail("The admitted operation did not reach the controlled authorization await") }
        XCTAssertFalse(subject.mayEditSelections())
        await subject.restore() // Overlap rejected, never queues a second writer.
        XCTAssertEqual(transport.writes.count, 1)
        let quitting = Task { await subject.prepareToQuit() }
        await Task.yield()
        XCTAssertEqual(transport.writes.count, 1)
        release?.resume()
        await applying.value
        let mayQuit = await quitting.value
        XCTAssertTrue(mayQuit)
        XCTAssertEqual(transport.writes.map(\.value), [0, 1])
        XCTAssertEqual(subject.state, .off)
    }

    func testFixedHelperCommandRequiresCompleteTerminationEvidence() throws {
        func outcome(status: Termination = .exited(0), complete: Bool = true,
                     truncated: Bool = false, stopped: Bool = true) -> CommandOutcome {
            CommandOutcome(stdout: Data(), stderr: Data(), termination: status,
                outputComplete: complete, outputTruncated: truncated, directChildStopped: stopped)
        }
        XCTAssertEqual(PMSetService.completion(outcome()), .completed(status: 0))
        for result in [outcome(status: .timedOut), outcome(complete: false),
                       outcome(truncated: true), outcome(stopped: false), outcome(status: .signaled(9))] {
            guard case .uncertain = PMSetService.completion(result) else { return XCTFail("Incomplete execution accepted") }
        }
        XCTAssertThrowsError(try PMSetService.writeRequest(cell: acNap, value: 25))
        let request = try PMSetService.writeRequest(cell: batteryNap, value: 1)
        XCTAssertEqual(request.executable, "/usr/bin/pmset")
        XCTAssertEqual(request.arguments, ["-b", "powernap", "1"])
    }

    func testUnavailableHelperDoesNotCreateExecutionFence() async {
        let store = EngineStore(), transport = EngineTransport([acNap: 1])
        transport.preflightError = RecoveryEvidenceError.invalid("Helper access unavailable")
        let subject = engine(store, transport)
        await subject.apply(settings: [.disablePowerNap])
        XCTAssertTrue(transport.writes.isEmpty)
        XCTAssertNil(store.fence)
        XCTAssertFalse(subject.executionUncertain)
        XCTAssertFalse(subject.state.isActive)
    }

    func testAuthenticatedRejectionRetainsEvidenceWithoutInventingExecution() async {
        let store = EngineStore(), transport = EngineTransport([acNap: 1])
        transport.onWrite = { _, _, _ in .notExecuted("Permission revoked before dispatch") }
        let subject = engine(store, transport)
        await subject.apply(settings: [.disablePowerNap])
        XCTAssertEqual(store.fence?.completed, true)
        XCTAssertFalse(subject.executionUncertain)
        XCTAssertEqual(transport.values[acNap], 1)
        XCTAssertFalse(subject.state.isActive)
    }
}
