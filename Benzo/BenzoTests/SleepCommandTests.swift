import Foundation
import XCTest

private enum SleepCommandFailure: Error { case injected }

private final class SleepCommandStore: PowerCommandStoring {
    var state = try! PowerCommandState.initial(owner: PowerCommandOwner(uid: 501, generatedUID: UUID()))
    var commits = 0
    var failCommit: Int?
    var events: [String] = []
    var afterCommit: (() -> Void)?
    func load() throws -> PowerCommandState { state }
    func commit(_ next: PowerCommandState) throws {
        commits += 1
        if failCommit == commits { throw SleepCommandFailure.injected }
        try next.validateTransition(from: state)
        state = next
        events.append(next.pendingSleep?.isTerminal == false ? "intent" : (next.pendingSleep == nil ? "ack" : "terminal"))
        afterCommit?()
    }
}

@MainActor
private final class SleepCommandHarness {
    let store: SleepCommandStore
    var boot = UUID()
    var now: UInt64 = 100
    var executions = 0
    var settingExecutions = 0
    var captures = 0
    var outcome: PowerSleepExecution = .completed(exitStatus: 0)
    var onExecute: (() async -> Void)?
    lazy var engine = PowerCommandEngine(store: store, bootID: { self.boot }, capture: { _ in
        self.captures += 1; return 1
    }, execute: { _, _ in self.settingExecutions += 1; return .completed(exitStatus: 0) },
    executeSleep: { _ in
        self.executions += 1; self.store.events.append("execute")
        await self.onExecute?()
        return self.outcome
    }, continuousTicks: { self.now }, maximumSleepLifetime: 30)
    init(store: SleepCommandStore = SleepCommandStore()) { self.store = store }
    func request(sequence: UInt64? = nil, expiry: UInt64 = 110, requestID: UUID = UUID(),
                 operationID: UUID = UUID(), bootID: UUID? = nil) -> PowerSleepRequest {
        PowerSleepRequest(grantEpoch: store.state.grantEpoch, sequence: sequence ?? store.state.highWaterMark + 1,
            requestID: requestID, operationID: operationID, bootID: bootID ?? boot, expiresAtContinuousTicks: expiry)
    }
    func setting(sequence: UInt64) -> PowerCommandRequest {
        PowerCommandRequest(grantEpoch: store.state.grantEpoch, sequence: sequence, requestID: UUID(),
            operationID: UUID(), bootID: boot, profile: .ac, key: .powernap, expectedValue: 1, target: 0)
    }
    func handle(_ input: PowerCommandInput) async -> PowerCommandReply { await engine.handle(input, caller: store.state.owner) }
}

@MainActor
final class SleepCommandTests: XCTestCase {
    func testIntentPrecedesOneFixedSleepChildAndLostReplyNeverReplays() async throws {
        let h = SleepCommandHarness()
        let request = h.request()
        let result = await h.handle(.sleep(request))
        XCTAssertEqual(h.store.events, ["intent", "execute", "terminal"])
        XCTAssertEqual(result.pendingSleep?.outcome, .completed(exitStatus: 0))
        XCTAssertEqual(result.sleepRequest, request)
        XCTAssertEqual(result.schema, 2)
        XCTAssertEqual(result.capabilities, ["sleep-v1"])
        let replacement = SleepCommandHarness(store: h.store)
        replacement.boot = h.boot
        let status = await replacement.handle(.status(request.token))
        let replay = await replacement.handle(.sleep(request))
        XCTAssertEqual(status.pendingSleep, result.pendingSleep)
        XCTAssertEqual(replay.pendingSleep, result.pendingSleep)
        XCTAssertEqual(replacement.executions, 0)
        XCTAssertEqual(h.captures, 0)
        XCTAssertNil(h.store.state.pending)
    }

    func testTerminalAckDowngradesSchemaWithoutResettingAuthorityAndAllowsSettings() async throws {
        let h = SleepCommandHarness()
        let before = h.store.state
        let request = h.request()
        _ = await h.handle(.sleep(request))
        let blocked = await h.handle(.write(h.setting(sequence: 2)))
        guard case .denied = blocked.outcome else { return XCTFail("Pending sleep must block settings") }
        let ack = await h.handle(.ack(request.token))
        XCTAssertEqual(ack.schema, 2)
        XCTAssertEqual(ack.outcome, .acknowledged)
        XCTAssertEqual(h.store.state.schema, 1)
        XCTAssertNil(h.store.state.pendingSleep)
        XCTAssertEqual(h.store.state.owner, before.owner)
        XCTAssertEqual(h.store.state.grantEpoch, before.grantEpoch)
        XCTAssertEqual(h.store.state.highWaterMark, 1)
        let version = await h.handle(.version)
        XCTAssertEqual(version.schema, 1)
        let setting = await h.handle(.write(h.setting(sequence: 2)))
        XCTAssertEqual(setting.outcome, .completed(exitStatus: 0))
        XCTAssertEqual(setting.schema, 1)
        _ = await h.handle(.sleep(request))
        XCTAssertEqual(h.executions, 1)
    }

    func testExpiryBeforeAdmissionIsDurablyNoSpawnAndCannotRevive() async {
        for expiry: UInt64 in [99, 100, 131, UInt64.max] {
            let h = SleepCommandHarness()
            let request = h.request(expiry: expiry)
            let result = await h.handle(.sleep(request))
            guard case .notExecuted = result.pendingSleep?.outcome else { return XCTFail("Invalid expiry must be sealed") }
            XCTAssertEqual(h.store.state.highWaterMark, 1)
            h.now = 98
            _ = await h.handle(.sleep(request))
            _ = await h.handle(.ack(request.token))
            _ = await h.handle(.sleep(request))
            XCTAssertEqual(h.executions, 0)
        }
    }

    func testExpiryBetweenIntentAndSpawnIsTerminalNoSpawn() async {
        let h = SleepCommandHarness()
        let request = h.request()
        h.store.afterCommit = { h.now = 110 }
        let result = await h.handle(.sleep(request))
        XCTAssertEqual(h.store.events, ["intent", "terminal"])
        guard case .notExecuted = result.pendingSleep?.outcome else { return XCTFail("Expired intent may not spawn") }
        XCTAssertEqual(h.executions, 0)
    }

    func testExpiredSealStatusAndAckNeverNeedFreshExpiryOrSpawn() async {
        let h = SleepCommandHarness()
        let request = h.request(expiry: 1, bootID: UUID())
        let sealed = await h.handle(.sealSleep(request))
        guard case .notExecuted = sealed.pendingSleep?.outcome else { return XCTFail("Seal must retire expired prior-boot input") }
        let status = await h.handle(.status(request.token))
        XCTAssertEqual(status.pendingSleep, sealed.pendingSleep)
        let ack = await h.handle(.ack(request.token))
        XCTAssertEqual(ack.outcome, .acknowledged)
        XCTAssertEqual(h.store.state.highWaterMark, 1)
        _ = await h.handle(.sleep(request))
        XCTAssertEqual(h.executions, 0)
    }

    func testUnprovedChildQuiescenceCannotAckOrReplayOnSameBoot() async {
        let h = SleepCommandHarness()
        h.outcome = .uncertain(reason: "Child lifetime not proved")
        let request = h.request()
        _ = await h.handle(.sleep(request))
        XCTAssertEqual(h.store.state.pendingSleep?.outcome, .intent)
        let fresh = SleepCommandHarness(store: h.store)
        fresh.boot = h.boot; fresh.now = 999
        _ = await fresh.handle(.sleep(request))
        _ = await fresh.handle(.sealSleep(request))
        let ack = await fresh.handle(.ack(request.token))
        guard case .denied = ack.outcome else { return XCTFail("Unproved child must remain fenced") }
        XCTAssertEqual(fresh.executions, 0)
        XCTAssertEqual(h.store.state.schema, 2)
    }

    func testReapedUnknownResultIsTerminalAndCanReleaseRestoration() async {
        let h = SleepCommandHarness()
        h.outcome = .childStoppedOutcomeUnknown(reason: "Child stopped; result unknown")
        let request = h.request()
        let result = await h.handle(.sleep(request))
        XCTAssertEqual(result.pendingSleep?.outcome, .childStoppedOutcomeUnknown(reason: "Child stopped; result unknown"))
        XCTAssertEqual(result.pendingSleep?.isTerminal, true)
        _ = await h.handle(.ack(request.token))
        let restore = await h.handle(.write(h.setting(sequence: 2)))
        XCTAssertEqual(restore.outcome, .completed(exitStatus: 0))
    }

    func testPriorBootSealProvesQuiescenceWithoutReadCaptureOrSleepSuccess() async {
        let h = SleepCommandHarness()
        h.outcome = .uncertain(reason: "Lost terminal status")
        let request = h.request()
        _ = await h.handle(.sleep(request))
        let replacement = SleepCommandHarness(store: h.store)
        replacement.now = 999
        let status = await replacement.handle(.status(request.token))
        XCTAssertEqual(status.pendingSleep?.outcome, .intent)
        let result = await replacement.handle(.sealSleep(request))
        XCTAssertEqual(result.pendingSleep?.outcome, .reconciledAfterBoot)
        XCTAssertEqual(result.pendingSleep?.request.bootID, request.bootID)
        XCTAssertEqual(replacement.captures, 0)
        XCTAssertEqual(replacement.executions, 0)
        _ = await replacement.handle(.ack(request.token))
        XCTAssertEqual(h.store.state.schema, 1)
    }

    func testFailuresAtIntentTerminalAndAckPreserveEvidence() async {
        for failedCommit in 1...3 {
            let h = SleepCommandHarness()
            h.store.failCommit = failedCommit
            let request = h.request()
            let result = await h.handle(.sleep(request))
            if failedCommit < 3 {
                guard case .uncertain = result.outcome else { return XCTFail("Failed publication cannot claim completion") }
            } else {
                let ack = await h.handle(.ack(request.token))
                guard case .uncertain = ack.outcome else { return XCTFail("Failed ACK cannot release evidence") }
            }
            XCTAssertEqual(h.executions, failedCommit == 1 ? 0 : 1)
            XCTAssertEqual(h.store.state.schema, failedCommit == 1 ? 1 : 2)
            if failedCommit == 2 { XCTAssertEqual(h.store.state.pendingSleep?.outcome, .intent) }
            if failedCommit == 3 { XCTAssertEqual(h.store.state.pendingSleep?.isTerminal, true) }
        }
    }

    func testDuplicateRequiresExactSleepIdentityAndNeverReplacesReceipt() async {
        let h = SleepCommandHarness()
        let request = h.request()
        _ = await h.handle(.sealSleep(request))
        for changed in [h.request(sequence: 1),
            h.request(sequence: 1, expiry: 111, requestID: request.requestID, operationID: request.operationID),
            h.request(sequence: 2, requestID: request.requestID, operationID: request.operationID)] {
            _ = await h.handle(.sleep(changed))
            XCTAssertEqual(h.store.state.pendingSleep?.request, request)
        }
        XCTAssertEqual(h.executions, 0)
    }

    func testSleepAdmissionRequiresOwnerEpochBootAndExactNextSharedSequence() async {
        let h = SleepCommandHarness()
        let request = h.request()
        let impostor = PowerCommandOwner(uid: h.store.state.owner.uid, generatedUID: UUID())
        let foreign = await h.engine.handle(.sleep(request), caller: impostor)
        XCTAssertEqual(foreign.outcome, .differentAccount)
        XCTAssertNil(foreign.owner)
        XCTAssertNil(foreign.pendingSleep)
        let otherEpoch = PowerSleepRequest(grantEpoch: UUID(), sequence: 1, requestID: UUID(),
            operationID: UUID(), bootID: h.boot, expiresAtContinuousTicks: 110)
        for invalid in [otherEpoch, h.request(sequence: 2), h.request(bootID: UUID())] {
            let result = await h.handle(.sleep(invalid))
            guard case .denied = result.outcome else { return XCTFail("Invalid sleep admission must be denied") }
        }
        XCTAssertEqual(h.store.commits, 0)
        let setting = h.setting(sequence: 1)
        _ = await h.handle(.write(setting))
        let blocked = await h.handle(.sleep(h.request(sequence: 2)))
        guard case .denied = blocked.outcome else { return XCTFail("A settings receipt occupies the same slot") }
        XCTAssertEqual(h.executions, 0)
        XCTAssertEqual(h.store.state.pending?.request, setting)
        _ = await h.handle(.ack(setting.token))
        h.store.state.highWaterMark = UInt64.max - 1
        let final = h.request(sequence: UInt64.max)
        _ = await h.handle(.sealSleep(final))
        _ = await h.handle(.ack(final.token))
        _ = await h.handle(.sleep(final))
        XCTAssertEqual(h.store.state.highWaterMark, UInt64.max)
        XCTAssertEqual(h.executions, 0)
    }

    func testRootReentrancyCannotSealOrAcknowledgeAnExecutingChild() async {
        let h = SleepCommandHarness()
        let request = h.request()
        var entered: CheckedContinuation<Void, Never>?
        var release: CheckedContinuation<Void, Never>?
        h.onExecute = {
            entered?.resume(); entered = nil
            await withCheckedContinuation { release = $0 }
        }
        let running = Task { await h.handle(.sleep(request)) }
        await withCheckedContinuation { entered = $0 }
        let seal = await h.handle(.sealSleep(request))
        let ack = await h.handle(.ack(request.token))
        guard case .uncertain = seal.outcome, case .uncertain = ack.outcome else {
            release?.resume(); _ = await running.value
            return XCTFail("Reentrancy cannot establish terminal evidence")
        }
        release?.resume(); _ = await running.value
        XCTAssertEqual(h.executions, 1)
    }

    func testStateSchemaRejectsMixedSlotsFabricatedCompletionAndDiscardedIntent() throws {
        let h = SleepCommandHarness()
        let initial = h.store.state
        var intent = initial
        intent.schema = 2; intent.highWaterMark = 1
        intent.pendingSleep = PowerSleepReceipt(request: h.request(), outcome: .intent)
        try intent.validateTransition(from: initial)
        var mixed = intent
        mixed.pending = PowerCommandReceipt(request: h.setting(sequence: 1), outcome: .intent)
        XCTAssertThrowsError(try mixed.validate())
        var wrongSchema = intent; wrongSchema.schema = 1
        XCTAssertThrowsError(try wrongSchema.validate())
        var noSleep = intent; noSleep.pendingSleep = nil
        XCTAssertThrowsError(try noSleep.validate())
        XCTAssertThrowsError(try initial.validateTransition(from: intent))
        var terminal = intent; terminal.pendingSleep!.outcome = .completed(exitStatus: 0)
        XCTAssertThrowsError(try terminal.validateTransition(from: initial))
        try terminal.validateTransition(from: intent)
        var ack = initial; ack.highWaterMark = 1
        try ack.validateTransition(from: terminal)
        XCTAssertThrowsError(try intent.validateTransition(from: ack))
    }

    func testStrictSleepWireRejectsClientArgvSettingsTimerAndAmbiguousExpiry() throws {
        let h = SleepCommandHarness()
        let request = h.request()
        let data = try JSONEncoder().encode(request)
        XCTAssertEqual(try PowerCommandWire.decode(verb: "sleep-v1", data: data), .sleep(request))
        XCTAssertEqual(try PowerCommandWire.decode(verb: "seal-sleep-v1", data: data), .sealSleep(request))
        let json = String(decoding: data, as: UTF8.self)
        for extra in ["argv", "path", "duration", "profile", "target"] {
            let changed = json.replacingOccurrences(of: "\"schema\":1", with: "\"schema\":1,\"\(extra)\":1")
            XCTAssertThrowsError(try PowerCommandWire.decode(verb: "sleep-v1", data: Data(changed.utf8)))
        }
        for expiry in ["0", "-1", "1.0", "1e1", "true", "\"110\"", "18446744073709551616", "110,\"expiresAtContinuousTicks\":110"] {
            let changed = json.replacingOccurrences(of: "\"expiresAtContinuousTicks\":110", with: "\"expiresAtContinuousTicks\":\(expiry)")
            XCTAssertThrowsError(try PowerCommandWire.decode(verb: "sleep-v1", data: Data(changed.utf8)))
        }
        XCTAssertThrowsError(try PowerCommandWire.decode(verb: "write-v1", data: data))
    }

    func testLegacyDecodersRejectSleepEvidenceAndAcknowledgementRestoresLegacyShape() async throws {
        // Frozen v1 validation, rather than a new decoder silently ignoring a new field.
        struct LegacyState: Decodable {
            let schema: Int
            let pending: PowerCommandReceipt?
            func validate() throws {
                guard schema == 1 else { throw SleepCommandFailure.injected }
            }
        }
        struct LegacyReply: Decodable {
            let schema: Int
            let protocolVersion: Int
            enum CodingKeys: String, CodingKey { case schema, protocolVersion = "protocol" }
            func validate() throws {
                guard schema == 1, protocolVersion == 1 else { throw SleepCommandFailure.injected }
            }
        }
        let h = SleepCommandHarness()
        let request = h.request()
        let sleepReply = await h.handle(.sealSleep(request))
        let oldReply = try JSONDecoder().decode(LegacyReply.self, from: JSONEncoder().encode(sleepReply))
        XCTAssertThrowsError(try oldReply.validate())
        let bytes = try JSONEncoder().encode(h.store.state)
        let old = try JSONDecoder().decode(LegacyState.self, from: bytes)
        XCTAssertThrowsError(try old.validate())
        XCTAssertEqual(try JSONDecoder().decode(PowerCommandState.self, from: bytes), h.store.state)
        _ = await h.handle(.ack(request.token))
        let acknowledged = try JSONEncoder().encode(h.store.state)
        try JSONDecoder().decode(LegacyState.self, from: acknowledged).validate()
        XCTAssertFalse(String(decoding: acknowledged, as: UTF8.self).contains("pendingSleep"))
        let missing = String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: "\"schema\":2", with: "\"schema\":1")
        XCTAssertThrowsError(try JSONDecoder().decode(PowerCommandState.self, from: Data(missing.utf8)))
    }

    func testRuntimeUsesOnlyFixedArgvAndRechecksExpiryAtChildCreation() {
        var now: UInt64 = 100
        var invocations = 0
        let result = CommandRuntime.executeSleep(expiresAtContinuousTicks: 110, runChild: { path, args, _, _, maySpawn in
            invocations += 1
            XCTAssertEqual(path, "/usr/bin/pmset")
            XCTAssertEqual(args, ["sleepnow"])
            now = 110
            XCTAssertFalse(maySpawn())
            return CommandRuntime.Result(stdout: Data(), stderr: Data(), exitStatus: nil,
                                         spawned: false, reaped: true, complete: false)
        }, continuousTicks: { now }, maximumLifetime: 30)
        guard case .notExecuted = result else { return XCTFail("Expired child must not spawn") }
        XCTAssertEqual(invocations, 1)
    }

    func testRuntimeSeparatesReapedUnknownOutcomeFromUnprovedChildQuiescence() {
        for reaped in [false, true] {
            let result = CommandRuntime.executeSleep(expiresAtContinuousTicks: 110, runChild: { _, _, _, _, maySpawn in
                XCTAssertTrue(maySpawn())
                return CommandRuntime.Result(stdout: Data(), stderr: Data(), exitStatus: nil,
                                             spawned: true, reaped: reaped, complete: false)
            }, continuousTicks: { 100 }, maximumLifetime: 30)
            if reaped {
                guard case .childStoppedOutcomeUnknown = result else { return XCTFail("Reaped child must be terminal") }
            } else {
                guard case .uncertain = result else { return XCTFail("Unproved child must remain fenced") }
            }
        }
    }
}
