import Foundation
import XCTest

private let helperBoot = "11111111-1111-4111-8111-111111111111"
private let helperLaterBoot = "22222222-2222-4222-8222-222222222222"
private let helperThirdBoot = "33333333-3333-4333-8333-333333333333"
private let helperCell = ManagedCell(profile: .ac, key: .powernap)
private let helperOwner = HelperOwner(uid: 501, generatedUID: UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!)

private final class FakeHelperStore: HelperAuthorityStoring {
    var state: HelperAuthorityState?
    var loadFails = false
    var failCommit: Int?
    var exposeFailedCommit = false
    var commits = 0

    func load() throws -> HelperAuthorityState? {
        if loadFails { throw HelperProtocolError.invalid("Injected store read failure") }
        return state
    }

    func commit(_ state: HelperAuthorityState) throws {
        commits += 1
        if commits == failCommit {
            if exposeFailedCommit { self.state = state }
            throw HelperProtocolError.invalid("Injected store commit failure")
        }
        self.state = state
    }
}

@MainActor
private final class HelperHarness {
    let store: FakeHelperStore
    var boot = helperBoot
    var value = 1
    var captures = 0
    var executions = 0
    var captureFails = false
    var bootFailsAfterExecution = false
    var peerRevalidations = 0
    var peerFailsOnValidation: Int?
    var onCapture: (() async -> Void)?
    var onExecute: (() async -> RecoveryWriteOutcome)?
    var outcome: RecoveryWriteOutcome = .completed(status: 0)

    lazy var engine = HelperEngine(store: store, buildIdentifier: "fixture-build", bootID: { [unowned self] in
        if bootFailsAfterExecution && executions > 0 { throw HelperProtocolError.invalid("Injected boot failure") }
        return boot
    }, capture: { [unowned self] in
        captures += 1
        await onCapture?()
        if captureFails { throw HelperProtocolError.invalid("Injected capture failure") }
        return try ProfileSnapshot(parsing: "AC Power:\n powernap \(value)\n")
    }, execute: { [unowned self] _, target in
        executions += 1
        if let onExecute { return await onExecute() }
        if outcome == .completed(status: 0) { value = target }
        return outcome
    }, revalidatePeer: { [unowned self] _ in
        peerRevalidations += 1
        if peerRevalidations == peerFailsOnValidation { throw HelperProtocolError.invalid("Injected account identity change") }
    })

    init(store: FakeHelperStore = FakeHelperStore()) { self.store = store }

    func enroll() throws { _ = try engine.enroll(peer: helperOwner, adminAuthorized: true) }

    func request(revision: UInt64 = 0, expected: Int = 1, target: Int = 0,
                 requestID: UUID = UUID(), operationID: UUID = UUID()) -> HelperWriteRequest {
        HelperWriteRequest(requestID: requestID, operationID: operationID, bootID: boot,
            cell: helperCell, expectedValue: expected, target: target, expectedRevision: revision)
    }
}

@MainActor
final class HelperEngineTests: XCTestCase {
    func testEnrollmentRequiresGrantAndCannotTransferAccount() throws {
        let h = HelperHarness()
        let initial = try h.engine.status(peer: helperOwner)
        XCTAssertNil(initial.owner)
        XCTAssertEqual(initial.revision, 0)
        XCTAssertFalse(initial.executionUncertain)
        XCTAssertThrowsError(try h.engine.enroll(peer: helperOwner, adminAuthorized: false))
        XCTAssertNil(h.store.state)
        try h.enroll()
        XCTAssertEqual(try h.engine.enroll(peer: helperOwner, adminAuthorized: false).owner, helperOwner)
        XCTAssertEqual(h.store.commits, 1, "Idempotent enrollment must not overwrite authority")
        for other in [HelperOwner(uid: 502, generatedUID: UUID()), HelperOwner(uid: 501, generatedUID: UUID())] {
            XCTAssertThrowsError(try h.engine.enroll(peer: other, adminAuthorized: true))
        }
        XCTAssertEqual(h.store.state?.owner, helperOwner)
    }

    func testOnlyEnrolledPrincipalMayWrite() async throws {
        let h = HelperHarness()
        assertNotExecuted(await h.engine.write(h.request(), peer: helperOwner))
        try h.enroll()
        for other in [HelperOwner(uid: 502, generatedUID: UUID()), HelperOwner(uid: 501, generatedUID: UUID())] {
            assertNotExecuted(await h.engine.write(h.request(), peer: other))
        }
        XCTAssertEqual(h.captures, 0)
        XCTAssertEqual(h.executions, 0)
    }

    func testDurableIntentPrecedesExecutionAndReplyFollowsDurableCompletion() async throws {
        let h = HelperHarness()
        try h.enroll()
        let request = h.request()
        h.onExecute = {
            XCTAssertEqual(h.store.state?.revision, 1)
            XCTAssertEqual(h.store.state?.lastExecution?.request, request)
            XCTAssertTrue(h.store.state?.lastExecution?.isIncomplete == true)
            return .completed(status: 0)
        }
        let reply = await h.engine.write(request, peer: helperOwner)
        XCTAssertEqual(reply.request, request)
        XCTAssertEqual(reply.outcome, .completed(exitStatus: 0))
        XCTAssertEqual(reply.revision, 1)
        XCTAssertEqual(h.store.state?.lastExecution?.completedStatus, 0)
        XCTAssertEqual(h.store.commits, 3)
    }

    func testReplacedAccountCannotTurnHistoricalExecutionIntoRejection() async throws {
        let h = HelperHarness()
        try h.enroll()
        let original = h.request()
        let applied = await h.engine.write(original, peer: helperOwner)
        XCTAssertEqual(applied.outcome, .completed(exitStatus: 0))
        let replacement = HelperOwner(uid: helperOwner.uid, generatedUID: UUID())
        assertUncertain(await h.engine.write(original, peer: replacement))
        assertUncertain(await h.engine.write(h.request(revision: 1, expected: 0, target: 1,
            requestID: original.requestID), peer: replacement))
        assertNotExecuted(await h.engine.write(h.request(revision: 1, expected: 0, target: 1), peer: replacement))
        _ = await h.engine.write(h.request(revision: 1, expected: 0, target: 1), peer: helperOwner)
        assertUncertain(await h.engine.write(original, peer: replacement))
        XCTAssertEqual(h.executions, 2, "Unauthorized historical requests must never execute again")
        XCTAssertEqual(h.captures, 2)
        XCTAssertEqual(h.store.state?.owner, helperOwner)
    }

    func testOldRequestCannotReplayAfterSettingsCycleBack() async throws {
        let h = HelperHarness()
        try h.enroll()
        let original = h.request()
        let applied = await h.engine.write(original, peer: helperOwner)
        let restored = await h.engine.write(h.request(revision: 1, expected: 0, target: 1), peer: helperOwner)
        XCTAssertEqual(applied.outcome, .completed(exitStatus: 0))
        XCTAssertEqual(restored.outcome, .completed(exitStatus: 0))
        XCTAssertEqual(h.value, 1, "The old request's precondition matches again")
        assertUncertain(await h.engine.write(original, peer: helperOwner))
        XCTAssertEqual(h.executions, 2, "A stale revision must still reject the old request")
        XCTAssertEqual(h.store.state?.revision, 2)
    }

    func testPreconditionAndDomainRejectionsNeverPersistIntent() async throws {
        let h = HelperHarness()
        try h.enroll()
        assertNotExecuted(await h.engine.write(h.request(expected: 0), peer: helperOwner))
        assertNotExecuted(await h.engine.write(h.request(target: 25), peer: helperOwner))
        assertNotExecuted(await h.engine.write(h.request(revision: UInt64.max), peer: helperOwner))
        var wrongSchema = h.request()
        wrongSchema.schema = 99
        assertNotExecuted(await h.engine.write(wrongSchema, peer: helperOwner))
        XCTAssertEqual(h.executions, 0)
        XCTAssertEqual(h.store.commits, 1)
    }

    func testAdmissionCoversCaptureAwaitAndEnrollment() async throws {
        let h = HelperHarness()
        try h.enroll()
        var resumeCapture: CheckedContinuation<Void, Never>?
        h.onCapture = { await withCheckedContinuation { resumeCapture = $0 } }
        let request = h.request()
        let first = Task { await h.engine.write(request, peer: helperOwner) }
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while resumeCapture == nil && ProcessInfo.processInfo.systemUptime < deadline { await Task.yield() }
        guard let release = resumeCapture else {
            h.onCapture = nil
            first.cancel()
            _ = await first.value
            return XCTFail("The injected capture was never reached")
        }
        assertNotExecuted(await h.engine.write(h.request(), peer: helperOwner))
        assertUncertain(await h.engine.write(request, peer: helperOwner))
        assertUncertain(await h.engine.write(h.request(target: 25, requestID: request.requestID), peer: helperOwner))
        XCTAssertThrowsError(try h.engine.enroll(peer: helperOwner, adminAuthorized: true))
        XCTAssertThrowsError(try h.engine.prepareForReplacement(peer: helperOwner))
        XCTAssertTrue(try h.engine.status(peer: helperOwner).executionUncertain)
        release.resume()
        let result = await first.value
        XCTAssertEqual(result.outcome, .completed(exitStatus: 0))
        XCTAssertEqual(h.executions, 1)
    }

    func testCompletedDuplicateReturnsReceiptAndChangedContentsRemainUncertain() async throws {
        let h = HelperHarness()
        try h.enroll()
        let request = h.request()
        let original = await h.engine.write(request, peer: helperOwner)
        let duplicate = await h.engine.write(request, peer: helperOwner)
        XCTAssertEqual(duplicate, original)
        assertUncertain(await h.engine.write(h.request(revision: 1, expected: 0, target: 1,
            requestID: request.requestID), peer: helperOwner))
        var invalidChanged = request
        invalidChanged.schema = 99
        assertUncertain(await h.engine.write(invalidChanged, peer: helperOwner))
        XCTAssertEqual(h.executions, 1)
    }

    func testDuplicateDuringExecutionCannotClaimNoDispatch() async throws {
        let h = HelperHarness()
        try h.enroll()
        var resumeExecution: CheckedContinuation<Void, Never>?
        h.onExecute = {
            await withCheckedContinuation { resumeExecution = $0 }
            return .completed(status: 0)
        }
        let request = h.request()
        let first = Task { await h.engine.write(request, peer: helperOwner) }
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while resumeExecution == nil && ProcessInfo.processInfo.systemUptime < deadline { await Task.yield() }
        guard let release = resumeExecution else {
            h.onExecute = nil
            first.cancel()
            _ = await first.value
            return XCTFail("The injected executor was never reached")
        }
        assertUncertain(await h.engine.write(request, peer: helperOwner))
        assertNotExecuted(await h.engine.write(h.request(revision: 1), peer: helperOwner))
        release.resume()
        let completed = await first.value
        XCTAssertEqual(completed.outcome, .completed(exitStatus: 0))
        XCTAssertEqual(h.executions, 1)
    }

    func testDaemonRestartDoesNotClearSameBootUncertainty() async throws {
        let first = HelperHarness()
        try first.enroll()
        first.outcome = .uncertain("Injected lost completion")
        assertUncertain(await first.engine.write(first.request(), peer: helperOwner))
        let restarted = HelperHarness(store: first.store)
        XCTAssertTrue(try restarted.engine.status(peer: helperOwner).executionUncertain)
        assertNotExecuted(await restarted.engine.write(restarted.request(revision: 1), peer: helperOwner))
        XCTAssertEqual(restarted.executions, 0)
        XCTAssertEqual(restarted.captures, 0)
    }

    func testLaterBootMustCaptureAndPreservePreviousUncertaintyBeforeAdmission() async throws {
        let h = HelperHarness()
        try h.enroll()
        h.outcome = .uncertain("Injected loss")
        assertUncertain(await h.engine.write(h.request(), peer: helperOwner))
        let old = try XCTUnwrap(h.store.state?.lastExecution)
        let restarted = HelperHarness(store: h.store)
        restarted.boot = helperLaterBoot
        restarted.captureFails = true
        assertNotExecuted(await restarted.engine.write(restarted.request(revision: 1), peer: helperOwner))
        XCTAssertEqual(restarted.store.state?.lastExecution, old)
        XCTAssertNil(restarted.store.state?.priorUncertainExecution)
        restarted.captureFails = false
        let completed = await restarted.engine.write(restarted.request(revision: 1), peer: helperOwner)
        XCTAssertEqual(completed.outcome, .completed(exitStatus: 0))
        XCTAssertEqual(restarted.store.state?.priorUncertainExecution, old)
        XCTAssertEqual(restarted.store.state?.revision, 2)
    }

    func testSecondUnresolvedRecordCannotDiscardRetainedEvidence() async throws {
        let h = HelperHarness()
        try h.enroll()
        h.outcome = .uncertain("First lost completion")
        _ = await h.engine.write(h.request(), peer: helperOwner)
        let old = h.store.state?.lastExecution
        h.boot = helperLaterBoot
        _ = await h.engine.write(h.request(revision: 1), peer: helperOwner)
        h.boot = helperThirdBoot
        XCTAssertTrue(try h.engine.status(peer: helperOwner).executionUncertain)
        assertNotExecuted(await h.engine.write(h.request(revision: 2), peer: helperOwner))
        XCTAssertEqual(h.executions, 2)
        XCTAssertEqual(h.store.state?.priorUncertainExecution, old)
    }

    func testIntentPersistenceFailurePoisonsEngineEvenIfRenameWasVisible() async throws {
        let h = HelperHarness()
        try h.enroll()
        h.store.failCommit = 2
        h.store.exposeFailedCommit = true
        assertUncertain(await h.engine.write(h.request(), peer: helperOwner))
        XCTAssertEqual(h.executions, 0)
        XCTAssertTrue(h.store.state?.lastExecution?.isIncomplete == true)
        h.store.failCommit = nil
        assertUncertain(await h.engine.write(h.request(revision: 1), peer: helperOwner))
        XCTAssertThrowsError(try h.engine.status(peer: helperOwner))
        XCTAssertEqual(h.executions, 0)
    }

    func testCompletionPersistenceFailureNeverReturnsSuccess() async throws {
        let h = HelperHarness()
        try h.enroll()
        h.store.failCommit = 3
        assertUncertain(await h.engine.write(h.request(), peer: helperOwner))
        XCTAssertEqual(h.executions, 1)
        XCTAssertTrue(h.store.state?.lastExecution?.isIncomplete == true)
        h.store.failCommit = nil
        assertUncertain(await h.engine.write(h.request(revision: 1, expected: 0, target: 1), peer: helperOwner))
        XCTAssertEqual(h.executions, 1)
    }

    func testReadFailurePoisonsEngineRatherThanBecomingUnenrolled() throws {
        let h = HelperHarness()
        h.store.loadFails = true
        XCTAssertThrowsError(try h.engine.status(peer: helperOwner))
        h.store.loadFails = false
        XCTAssertThrowsError(try h.engine.enroll(peer: helperOwner, adminAuthorized: true))
        XCTAssertNil(h.store.state)
    }

    func testBootReadFailureAfterExecutionIsUncertainNotNotExecuted() async throws {
        let h = HelperHarness()
        try h.enroll()
        h.bootFailsAfterExecution = true
        assertUncertain(await h.engine.write(h.request(), peer: helperOwner))
        XCTAssertEqual(h.executions, 1)
        XCTAssertTrue(h.store.state?.lastExecution?.isIncomplete == true)
    }

    func testAuthoritativeNoDispatchReceiptDoesNotInventExitStatus() async throws {
        let h = HelperHarness()
        try h.enroll()
        h.outcome = .notExecuted("The executable was never launched")
        assertNotExecuted(await h.engine.write(h.request(), peer: helperOwner))
        XCTAssertNil(h.store.state?.lastExecution?.completedStatus)
        XCTAssertEqual(h.store.state?.lastExecution?.notExecutedReason, "The executable was never launched")
        XCTAssertFalse(try h.engine.status(peer: helperOwner).executionUncertain)
    }

    func testInvalidCompletionRemainsFenced() async throws {
        let h = HelperHarness()
        try h.enroll()
        h.outcome = .completed(status: 256)
        assertUncertain(await h.engine.write(h.request(), peer: helperOwner))
        XCTAssertTrue(try h.engine.status(peer: helperOwner).executionUncertain)
    }

    func testWireBoundsAndRootRecordConsistencyRejectMalformedEvidence() throws {
        let h = HelperHarness()
        let request = h.request()
        let encoded = try HelperProtocolLimits.encode(request)
        XCTAssertEqual(try HelperProtocolLimits.decode(HelperWriteRequest.self, from: encoded), request)
        XCTAssertThrowsError(try HelperProtocolLimits.decode(HelperWriteRequest.self, from: Data()))
        XCTAssertThrowsError(try HelperProtocolLimits.decode(HelperWriteRequest.self, from: Data(repeating: 32, count: 16_385)))
        let invalidKey = String(decoding: encoded, as: UTF8.self).replacingOccurrences(of: "powernap", with: "sleep")
        XCTAssertThrowsError(try HelperProtocolLimits.decode(HelperWriteRequest.self, from: Data(invalidKey.utf8)))
        XCTAssertThrowsError(try HelperAuthorityState(owner: helperOwner, revision: 1, lastExecution: nil).validate())
        XCTAssertThrowsError(try HelperAuthorityState(owner: helperOwner, revision: 2,
            lastExecution: HelperExecutionFence(request: request)).validate())
        var receipt = HelperExecutionFence(request: request, completedStatus: 0)
        receipt.notExecutedReason = "Contradictory receipt"
        XCTAssertThrowsError(try receipt.validate())
        let combining = "a" + String(repeating: "\u{0301}", count: 1000)
        XCTAssertLessThanOrEqual(HelperProtocolLimits.reason(combining).utf8.count, HelperProtocolLimits.maximumReasonBytes)
    }

    func testAccountIdentityIsRevalidatedAfterCaptureBeforeIntent() async throws {
        let h = HelperHarness()
        try h.enroll()
        // Enrollment performs the first validation, preflight the second, and
        // the validation after the asynchronous capture must reject the third.
        h.peerFailsOnValidation = 3
        assertNotExecuted(await h.engine.write(h.request(), peer: helperOwner))
        XCTAssertEqual(h.captures, 1)
        XCTAssertEqual(h.executions, 0)
        XCTAssertEqual(h.store.commits, 1)
    }

    func testResponseValidationRequiresCompleteIdentityRevisionAndStatus() throws {
        let h = HelperHarness()
        let request = h.request()
        let success = HelperWriteReply(request: request, outcome: .completed(exitStatus: 0), revision: 1)
        XCTAssertEqual(try success.validatedOutcome(for: request), .completed(status: 0))
        for malformed in [
            HelperWriteReply(schema: 2, request: request, outcome: .completed(exitStatus: 0), revision: 1),
            HelperWriteReply(request: h.request(), outcome: .completed(exitStatus: 0), revision: 1),
            HelperWriteReply(request: request, outcome: .completed(exitStatus: 0), revision: 0),
            HelperWriteReply(request: request, outcome: .completed(exitStatus: 256), revision: 1),
            HelperWriteReply(request: request, outcome: .notExecuted(reason: "Unknown old request"), revision: 2)
        ] {
            XCTAssertThrowsError(try malformed.validatedOutcome(for: request))
        }
        for revision: UInt64 in [0, 1] {
            XCTAssertEqual(try HelperWriteReply(request: request, outcome: .notExecuted(reason: "Not dispatched"), revision: revision)
                .validatedOutcome(for: request), .notExecuted("Not dispatched"))
        }
    }

    func testReplacementPreparationPausesOnlyNewRequestsWithoutChangingEvidence() async throws {
        let h = HelperHarness()
        try h.enroll()
        let request = h.request()
        let original = await h.engine.write(request, peer: helperOwner)
        let before = h.store.state
        let commits = h.store.commits
        let ready = try h.engine.prepareForReplacement(peer: helperOwner)
        XCTAssertEqual(ready.buildIdentifier, "fixture-build")
        XCTAssertTrue(ready.replacementPrepared)
        XCTAssertFalse(ready.executionUncertain)
        XCTAssertEqual(try h.engine.prepareForReplacement(peer: helperOwner), ready)
        assertNotExecuted(await h.engine.write(h.request(revision: 1, expected: 0, target: 1), peer: helperOwner))
        let duplicate = await h.engine.write(request, peer: helperOwner)
        XCTAssertEqual(duplicate, original)
        assertUncertain(await h.engine.write(h.request(revision: 1, expected: 0, target: 1,
            requestID: request.requestID), peer: helperOwner))
        assertUncertain(await h.engine.write(h.request(), peer: helperOwner))
        XCTAssertEqual(h.store.state, before)
        XCTAssertEqual(h.store.commits, commits)
        XCTAssertEqual(h.executions, 1)
        let replacement = HelperHarness(store: h.store)
        XCTAssertFalse(try replacement.engine.status(peer: helperOwner).replacementPrepared)
    }

    func testReplacementPreparationRejectsWrongOwnerUncertaintyAndPoisonedStore() async throws {
        let h = HelperHarness()
        XCTAssertThrowsError(try h.engine.prepareForReplacement(peer: helperOwner))
        try h.enroll()
        XCTAssertThrowsError(try h.engine.prepareForReplacement(peer: HelperOwner(uid: 501, generatedUID: UUID())))
        XCTAssertFalse(try h.engine.status(peer: helperOwner).replacementPrepared)
        h.outcome = .uncertain("Injected lost completion")
        _ = await h.engine.write(h.request(), peer: helperOwner)
        XCTAssertThrowsError(try h.engine.prepareForReplacement(peer: helperOwner))
        XCTAssertFalse(try h.engine.status(peer: helperOwner).replacementPrepared)
        h.store.loadFails = true
        XCTAssertThrowsError(try h.engine.prepareForReplacement(peer: helperOwner))
        h.store.loadFails = false
        XCTAssertThrowsError(try h.engine.prepareForReplacement(peer: helperOwner))
    }

    func testReplacementPreparationRevalidatesAccountBeforePausing() throws {
        let h = HelperHarness()
        try h.enroll()
        h.peerFailsOnValidation = 2
        XCTAssertThrowsError(try h.engine.prepareForReplacement(peer: helperOwner))
        XCTAssertFalse(try h.engine.status(peer: helperOwner).replacementPrepared)
        XCTAssertEqual(h.store.commits, 1)
    }

    private func assertNotExecuted(_ reply: HelperWriteReply, file: StaticString = #filePath, line: UInt = #line) {
        guard case .notExecuted = reply.outcome else { return XCTFail("Expected a no-dispatch reply: \(reply.outcome)", file: file, line: line) }
    }

    private func assertUncertain(_ reply: HelperWriteReply, file: StaticString = #filePath, line: UInt = #line) {
        guard case .uncertain = reply.outcome else { return XCTFail("Expected uncertainty: \(reply.outcome)", file: file, line: line) }
    }
}
