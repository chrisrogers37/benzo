import Foundation
import XCTest

private let commandOwner = PowerCommandOwner(uid: 501, generatedUID: UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!)
private let commandEpoch = UUID(uuidString: "EEEEEEEE-EEEE-4EEE-8EEE-EEEEEEEEEEEE")!
private let commandBoot = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!

private enum CommandTestFailure: Error { case injected }

private final class CommandMemoryStore: PowerCommandStoring {
    var state = try! PowerCommandState.initial(owner: commandOwner, grantEpoch: commandEpoch)
    var commits = 0
    var failCommit: Int?
    var events: [String] = []
    func load() throws -> PowerCommandState { state }
    func commit(_ next: PowerCommandState) throws {
        commits += 1
        if failCommit == commits { throw CommandTestFailure.injected }
        try next.validateTransition(from: state)
        state = next
        events.append(next.pending?.isTerminal == false ? "intent" : (next.pending == nil ? "ack" : "terminal"))
    }
}

@MainActor
private final class CommandHarness {
    let store: CommandMemoryStore
    var boot = commandBoot
    var observed: Int? = 1
    var outcome: PowerCommandExecution = .completed(exitStatus: 0)
    var captures = 0
    var executions = 0
    var validations = 0
    var failValidation: Int?
    var onCapture: (() async -> Void)?
    var onExecute: (() async -> Void)?
    lazy var engine = PowerCommandEngine(store: store, bootID: { self.boot }, capture: { _ in
        self.captures += 1
        self.store.events.append("capture")
        await self.onCapture?()
        return self.observed
    }, execute: { _, _ in
        self.executions += 1
        self.store.events.append("execute")
        await self.onExecute?()
        return self.outcome
    }, revalidateOwner: { _ in
        self.validations += 1
        if self.validations == self.failValidation { throw CommandTestFailure.injected }
    })

    init(store: CommandMemoryStore = CommandMemoryStore()) { self.store = store }
    func request(sequence: UInt64 = 1, epoch: UUID = commandEpoch, boot: UUID = commandBoot,
                 requestID: UUID = UUID(), operationID: UUID = UUID(), profile: PowerProfile = .ac,
                 key: ManagedKey = .powernap, expected: Int = 1, target: Int = 0) -> PowerCommandRequest {
        PowerCommandRequest(grantEpoch: epoch, sequence: sequence, requestID: requestID,
            operationID: operationID, bootID: boot, profile: profile, key: key, expectedValue: expected, target: target)
    }
    func handle(_ input: PowerCommandInput, owner: PowerCommandOwner = commandOwner) async -> PowerCommandReply {
        await engine.handle(input, caller: owner)
    }
}

@MainActor
final class CommandToolEngineTests: XCTestCase {
    func testIntentPrecedesExactlyOneExecutionAndDurableCompletionSurvivesClientCrash() async throws {
        let h = CommandHarness()
        let request = h.request()
        let reply = await h.handle(.write(request))
        XCTAssertEqual(reply.outcome, .completed(exitStatus: 0))
        XCTAssertEqual(h.store.events, ["capture", "intent", "execute", "terminal"])
        XCTAssertEqual(reply.request, request)
        let replacement = CommandHarness(store: h.store)
        let status = await replacement.handle(.status(request.token))
        XCTAssertEqual(status.outcome, .completed(exitStatus: 0))
        XCTAssertEqual(status.request, request)
        let duplicate = await replacement.handle(.write(request))
        XCTAssertEqual(duplicate.outcome, .completed(exitStatus: 0))
        XCTAssertEqual(replacement.executions, 0)
    }

    func testStatusBeforeLateWriteDoesNotClaimNoExecutionOrConsumeSequence() async {
        let h = CommandHarness()
        let request = h.request()
        uncertain(await h.handle(.status(request.token)))
        XCTAssertEqual(h.store.state.highWaterMark, 0)
        XCTAssertNil(h.store.state.pending)
        let late = await h.handle(.write(request))
        XCTAssertEqual(late.outcome, .completed(exitStatus: 0))
        XCTAssertEqual(h.executions, 1)
    }

    func testSealBeforeLateWriteBarsExecutionAfterAcknowledgementToo() async {
        let h = CommandHarness()
        let request = h.request()
        noExecution(await h.handle(.seal(request)))
        noExecution(await h.handle(.write(request)))
        let ack = await h.handle(.ack(request.token))
        XCTAssertEqual(ack.outcome, .acknowledged)
        XCTAssertNil(h.store.state.pending)
        XCTAssertEqual(h.store.state.highWaterMark, 1)
        uncertain(await h.handle(.write(request)))
        uncertain(await h.handle(.seal(request)))
        XCTAssertEqual(h.executions, 0)
        XCTAssertEqual(h.captures, 0)
    }

    func testWriteBeforeSealReturnsRetainedTerminalWithoutSecondSpawn() async {
        let h = CommandHarness()
        let request = h.request()
        let write = await h.handle(.write(request))
        let seal = await h.handle(.seal(request))
        XCTAssertEqual(write, seal)
        XCTAssertEqual(h.executions, 1)
    }

    func testReentrantSealDuringChildNeverClaimsNoExecution() async {
        let h = CommandHarness()
        let request = h.request()
        var entered: CheckedContinuation<Void, Never>?
        var release: CheckedContinuation<Void, Never>?
        h.onExecute = {
            entered?.resume(); entered = nil
            await withCheckedContinuation { release = $0 }
        }
        let executing = Task { await h.handle(.write(request)) }
        await withCheckedContinuation { entered = $0 }
        uncertain(await h.handle(.seal(request)))
        XCTAssertEqual(h.store.state.pending?.outcome, .intent)
        release?.resume()
        let finished = await executing.value
        XCTAssertEqual(finished.outcome, .completed(exitStatus: 0))
        XCTAssertEqual(h.executions, 1)
    }

    func testUncertainIntentIsNeverReplayedOrAcknowledgedOnSameBoot() async {
        let h = CommandHarness()
        h.outcome = .uncertain(reason: "Owned child termination is unknown")
        let request = h.request()
        uncertain(await h.handle(.write(request)))
        let replacement = CommandHarness(store: h.store)
        uncertain(await replacement.handle(.write(request)))
        uncertain(await replacement.handle(.seal(request)))
        denied(await replacement.handle(.ack(request.token)))
        XCTAssertEqual(replacement.executions, 0)
        XCTAssertEqual(h.store.state.pending?.outcome, .intent)
    }

    func testLateDuplicateAcknowledgementDoesNotReleaseNewReceiptOrRenewCompletion() async {
        let h = CommandHarness()
        let first = h.request()
        _ = await h.handle(.write(first))
        _ = await h.handle(.ack(first.token))
        let second = h.request(sequence: 2)
        _ = await h.handle(.write(second))
        let duplicateAck = await h.handle(.ack(first.token))
        XCTAssertEqual(duplicateAck.outcome, .acknowledged)
        XCTAssertEqual(h.store.state.pending?.request, second)
        uncertain(await h.handle(.status(first.token)))
        uncertain(await h.handle(.write(first)))
        XCTAssertEqual(h.executions, 2)
    }

    func testWrongOwnerIncludingReusedUIDCannotReadWriteOrAcknowledge() async {
        let h = CommandHarness()
        let request = h.request()
        _ = await h.handle(.seal(request))
        let original = h.store.state
        for owner in [PowerCommandOwner(uid: 502, generatedUID: commandOwner.generatedUID),
                      PowerCommandOwner(uid: commandOwner.uid, generatedUID: UUID())] {
            for input: PowerCommandInput in [.version, .status(request.token), .write(request), .seal(request), .ack(request.token)] {
                let reply = await h.handle(input, owner: owner)
                XCTAssertEqual(reply.outcome, .differentAccount)
                XCTAssertNil(reply.owner)
                XCTAssertNil(reply.pending)
                XCTAssertNil(reply.grantEpoch)
                XCTAssertNil(reply.highWaterMark)
            }
        }
        XCTAssertEqual(h.store.state, original)
        XCTAssertEqual(h.executions, 0)
    }

    func testPendingTerminalBlocksNextWriteUntilExactAck() async {
        let h = CommandHarness()
        let request = h.request()
        _ = await h.handle(.write(request))
        denied(await h.handle(.write(h.request(sequence: 2))))
        denied(await h.handle(.ack(h.request().token)))
        XCTAssertEqual(h.store.state.pending?.request, request)
        _ = await h.handle(.ack(request.token))
        let next = await h.handle(.write(h.request(sequence: 2)))
        XCTAssertEqual(next.outcome, .completed(exitStatus: 0))
        XCTAssertEqual(h.executions, 2)
    }

    func testFailedIntentCommitNeverCallsExecutorAndDoesNotClaimNoExecution() async {
        let h = CommandHarness()
        h.store.failCommit = 1
        let request = h.request()
        uncertain(await h.handle(.write(request)))
        XCTAssertEqual(h.executions, 0)
        XCTAssertEqual(h.store.state.highWaterMark, 0)
        XCTAssertNil(h.store.state.pending)
        uncertain(await h.handle(.write(request)))
        XCTAssertEqual(h.store.commits, 1, "A poisoned process cannot retry publication")
    }

    func testFailedTerminalCommitLeavesIntentAndCannotReportCompleted() async {
        let h = CommandHarness()
        h.store.failCommit = 2
        let request = h.request()
        uncertain(await h.handle(.write(request)))
        XCTAssertEqual(h.executions, 1)
        XCTAssertEqual(h.store.state.pending?.outcome, .intent)
        let replacement = CommandHarness(store: h.store)
        uncertain(await replacement.handle(.status(request.token)))
        uncertain(await replacement.handle(.write(request)))
        XCTAssertEqual(replacement.executions, 0)
    }

    func testPreconditionMismatchIsDurablySealedAndDelayedCopyCannotExecute() async {
        let h = CommandHarness()
        h.observed = 0
        let request = h.request()
        noExecution(await h.handle(.write(request)))
        h.observed = 1
        noExecution(await h.handle(.write(request)))
        XCTAssertEqual(h.executions, 0)
        XCTAssertEqual(h.store.state.highWaterMark, 1)
    }

    func testFutureEpochAndBootMismatchDoNotCreateIntent() async {
        let h = CommandHarness()
        for request in [h.request(sequence: 2), h.request(epoch: UUID())] {
            denied(await h.handle(.write(request)))
            denied(await h.handle(.seal(request)))
        }
        denied(await h.handle(.write(h.request(boot: UUID()))))
        XCTAssertEqual(h.executions, 0)
        XCTAssertEqual(h.captures, 0)
        XCTAssertEqual(h.store.commits, 0)
    }

    func testExplicitSealCanRetirePriorBootTokenWhoseIntentNeverArrived() async {
        let h = CommandHarness()
        h.boot = UUID()
        let request = h.request()
        uncertain(await h.handle(.status(request.token)))
        noExecution(await h.handle(.seal(request)))
        XCTAssertEqual(h.store.state.pending?.request, request)
        _ = await h.handle(.ack(request.token))
        uncertain(await h.handle(.write(request)))
        XCTAssertEqual(h.executions, 0)
        XCTAssertEqual(h.captures, 0)
        XCTAssertEqual(h.store.state.highWaterMark, 1)
    }

    func testOwnerOrBootChangeDuringCaptureCannotDispatch() async {
        for changeBoot in [false, true] {
            let h = CommandHarness()
            if changeBoot { h.onCapture = { h.boot = UUID() } }
            else { h.failValidation = 2 }
            uncertain(await h.handle(.write(h.request())))
            XCTAssertEqual(h.executions, 0)
            XCTAssertEqual(h.store.commits, 0)
        }
    }

    func testDuplicatePayloadMustMatchEntireTuple() async {
        let h = CommandHarness()
        let request = h.request()
        _ = await h.handle(.write(request))
        for changed in [
            h.request(requestID: request.requestID, operationID: UUID()),
            h.request(requestID: request.requestID, operationID: request.operationID, profile: .battery),
            h.request(requestID: request.requestID, operationID: request.operationID, key: .standby),
            h.request(requestID: request.requestID, operationID: request.operationID, expected: 0),
            h.request(requestID: request.requestID, operationID: request.operationID, target: 1),
            h.request(sequence: 2, requestID: request.requestID, operationID: request.operationID)
        ] { uncertain(await h.handle(.write(changed))) }
        XCTAssertEqual(h.executions, 1)
        XCTAssertEqual(h.store.state.pending?.request, request)
    }

    func testLaterBootNeedsExplicitReadOnlySealToReconcileIntent() async {
        let h = CommandHarness()
        h.outcome = .uncertain(reason: "Lost terminal status")
        let request = h.request()
        _ = await h.handle(.write(request))
        let replacement = CommandHarness(store: h.store)
        replacement.boot = UUID()
        replacement.observed = 0
        uncertain(await replacement.handle(.status(request.token)))
        uncertain(await replacement.handle(.write(request)))
        XCTAssertEqual(replacement.captures, 0)
        let reconciled = await replacement.handle(.seal(request))
        XCTAssertEqual(reconciled.outcome, .reconciledAfterBoot(observedValue: 0))
        XCTAssertEqual(reconciled.request?.bootID, commandBoot)
        XCTAssertEqual(replacement.captures, 1)
        XCTAssertEqual(replacement.executions, 0)
        _ = await replacement.handle(.ack(request.token))
        XCTAssertNil(h.store.state.pending)
        XCTAssertEqual(h.store.state.highWaterMark, 1)
    }

    func testLaterBootReconciliationRequiresValidCaptureAndFailedCommitStaysUncertain() async {
        for failCommit in [false, true] {
            let h = CommandHarness()
            h.outcome = .uncertain(reason: "No terminal status")
            let request = h.request()
            _ = await h.handle(.write(request))
            let replacement = CommandHarness(store: h.store)
            replacement.boot = UUID()
            if failCommit { h.store.failCommit = 2 } else { replacement.observed = nil }
            uncertain(await replacement.handle(.seal(request)))
            XCTAssertEqual(h.store.state.pending?.outcome, .intent)
            XCTAssertEqual(replacement.executions, 0)
        }
    }

    func testCounterSaturationDoesNotWrapAndRetiredPayloadIsNotRecreated() async {
        let h = CommandHarness()
        h.store.state.highWaterMark = UInt64.max - 1
        let request = h.request(sequence: UInt64.max)
        noExecution(await h.handle(.seal(request)))
        _ = await h.handle(.ack(request.token))
        uncertain(await h.handle(.write(request)))
        uncertain(await h.handle(.write(h.request())))
        XCTAssertEqual(h.store.state.highWaterMark, UInt64.max)
        XCTAssertNil(h.store.state.pending)
        XCTAssertEqual(h.executions, 0)
    }

    func testProvenNonzeroExitAndSpawnFailureAreDistinctTerminalOutcomes() async {
        for outcome: PowerCommandExecution in [.completed(exitStatus: 7), .notExecuted(reason: "Spawn rejected")] {
            let h = CommandHarness()
            h.outcome = outcome
            let reply = await h.handle(.write(h.request()))
            if case .completed = outcome { XCTAssertEqual(reply.outcome, .completed(exitStatus: 7)) }
            else { noExecution(reply) }
            XCTAssertTrue(h.store.state.pending?.isTerminal == true)
        }
        let h = CommandHarness()
        h.outcome = .completed(exitStatus: 256)
        uncertain(await h.handle(.write(h.request())))
        XCTAssertEqual(h.store.state.pending?.outcome, .intent)
    }

    func testVersionExposesOnlyAuthenticatedGrantAndRetainedSlot() async {
        let h = CommandHarness()
        let request = h.request()
        _ = await h.handle(.seal(request))
        let version = await h.handle(.version)
        XCTAssertEqual(version.outcome, .version)
        XCTAssertEqual(version.owner, commandOwner)
        XCTAssertEqual(version.grantEpoch, commandEpoch)
        XCTAssertEqual(version.highWaterMark, 1)
        XCTAssertEqual(version.pending?.request, request)
    }

    func testWireAcceptsExactlyAllFortyFiveTargetTuplesAndBothValueDomains() throws {
        let h = CommandHarness()
        var tuples = 0
        for profile in PowerProfile.allCases {
            for key in ManagedKey.allCases {
                let values = key == .hibernatemode ? [0, 3, 25] : [0, 1]
                for target in values {
                    tuples += 1
                    for expected in values {
                        let request = h.request(profile: profile, key: key, expected: expected, target: target)
                        let bytes = try JSONEncoder().encode(request)
                        XCTAssertEqual(try PowerCommandWire.decode(verb: "write-v1", data: bytes), .write(request))
                        XCTAssertEqual(try PowerCommandWire.decode(verb: "seal-v1", data: bytes), .seal(request))
                    }
                }
                for request in [h.request(profile: profile, key: key, expected: 2), h.request(profile: profile, key: key, target: 2)] {
                    XCTAssertThrowsError(try request.validate())
                }
            }
        }
        XCTAssertEqual(tuples, 45)
    }

    func testStrictWireRejectsDuplicatesUnknownKeysNULTrailingAndNonIntegers() throws {
        let h = CommandHarness()
        let json = String(decoding: try JSONEncoder().encode(h.request()), as: UTF8.self)
        let bad = [
            json.replacingOccurrences(of: "\"schema\":1", with: "\"schema\":1,\"schema\":1"),
            json.replacingOccurrences(of: "\"schema\":1", with: "\"schema\":1,\"sch\\u0065ma\":1"),
            json.replacingOccurrences(of: "\"schema\":1", with: "\"schema\":1,\"uid\":501"),
            json.replacingOccurrences(of: "\"sequence\":1", with: "\"sequence\":1.0"),
            json.replacingOccurrences(of: "\"sequence\":1", with: "\"sequence\":1e0"),
            json.replacingOccurrences(of: "\"sequence\":1", with: "\"sequence\":true"),
            json.replacingOccurrences(of: "\"sequence\":1", with: "\"sequence\":\"1\""),
            json.replacingOccurrences(of: "\"sequence\":1", with: "\"sequence\":-1"),
            json.replacingOccurrences(of: "\"sequence\":1", with: "\"sequence\":01"),
            json.replacingOccurrences(of: "\"sequence\":1", with: "\"sequence\":18446744073709551616"),
            json.replacingOccurrences(of: "\"target\":0", with: "\"target\":-0"),
            json.replacingOccurrences(of: "powernap", with: "power\\u0000nap"),
            json.replacingOccurrences(of: "\"schema\":1", with: "\"schema\":{}"),
            json + "{}", json + "\0", "[]", "null", "{}", ""
        ]
        for payload in bad {
            XCTAssertThrowsError(try PowerCommandWire.decode(verb: "write-v1", data: Data(payload.utf8)), payload)
        }
        XCTAssertThrowsError(try PowerCommandWire.decode(verb: "write-v1", data: Data(repeating: 32, count: 4_097)))
        XCTAssertThrowsError(try PowerCommandWire.decode(verb: "pmset", data: Data(json.utf8)))
        XCTAssertEqual(try PowerCommandWire.decode(verb: "version-v1", data: Data()), .version)
        XCTAssertEqual(try PowerCommandWire.decode(verb: "version-v1", data: Data("{\"schema\":1,\"protocol\":1}".utf8)), .version)
        let token = h.request(sequence: UInt64.max).token
        XCTAssertEqual(try PowerCommandWire.decode(verb: "status-v1", data: JSONEncoder().encode(token)), .status(token))
        XCTAssertEqual(try PowerCommandWire.decode(verb: "ack-v1", data: JSONEncoder().encode(token)), .ack(token))
    }

    func testStateTransitionsCannotReplaceGrantReceiptOrDiscardIntent() throws {
        let h = CommandHarness()
        let original = h.store.state
        var intent = original
        intent.highWaterMark = 1
        intent.pending = PowerCommandReceipt(request: h.request(), outcome: .intent)
        try intent.validateTransition(from: original)
        var discarded = intent
        discarded.pending = nil
        XCTAssertThrowsError(try discarded.validateTransition(from: intent))
        var replaced = intent
        replaced.pending = PowerCommandReceipt(request: h.request(), outcome: .intent)
        XCTAssertThrowsError(try replaced.validateTransition(from: intent))
        XCTAssertThrowsError(try original.validateTransition(from: intent))
        var forgedCompletion = intent
        forgedCompletion.pending!.outcome = .completed(exitStatus: 0)
        XCTAssertThrowsError(try forgedCompletion.validateTransition(from: original))
        try forgedCompletion.validateTransition(from: intent)
        try discarded.validateTransition(from: forgedCompletion)
        XCTAssertThrowsError(try forgedCompletion.validateTransition(from: discarded))
    }

    private func uncertain(_ reply: PowerCommandReply, file: StaticString = #filePath, line: UInt = #line) {
        guard case .uncertain = reply.outcome else { return XCTFail("Expected uncertainty: \(reply.outcome)", file: file, line: line) }
    }
    private func denied(_ reply: PowerCommandReply, file: StaticString = #filePath, line: UInt = #line) {
        guard case .denied = reply.outcome else { return XCTFail("Expected admission denial: \(reply.outcome)", file: file, line: line) }
    }
    private func noExecution(_ reply: PowerCommandReply, file: StaticString = #filePath, line: UInt = #line) {
        guard case .notExecuted = reply.outcome else { return XCTFail("Expected durable no-spawn receipt: \(reply.outcome)", file: file, line: line) }
    }
}
