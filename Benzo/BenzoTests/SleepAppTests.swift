import Darwin
import Foundation
import XCTest

@MainActor
final class SleepAppTests: XCTestCase {
    private func activeHarness() async -> (FakeDependencies, BenzoViewModel) {
        let harness = FakeDependencies()
        let viewModel = harness.makeViewModel()
        await viewModel.reconcile()
        await harness.coordinator.apply(settings: [.disablePowerNap])
        XCTAssertTrue(viewModel.canSleep)
        return (harness, viewModel)
    }

    func testAllPresetsFireOnceAndNeverPersistSchedulingState() {
        for minutes in SleepCountdown.presets {
            let scheduler = FakeSleepScheduler()
            let countdown = SleepCountdown(scheduler: scheduler)
            var fires = 0
            countdown.onFire = { fires += 1 }
            countdown.start(minutes: minutes)
            XCTAssertEqual(countdown.remainingSeconds, minutes * 60)
            scheduler.advance(seconds: minutes * 60 - 1)
            XCTAssertEqual(fires, 0)
            scheduler.advance(seconds: 1)
            XCTAssertEqual(fires, 1)
            XCTAssertNil(countdown.remainingSeconds)
            scheduler.advance(seconds: 10)
            XCTAssertEqual(fires, 1)
        }
    }

    func testCancelAndReplacementRejectAlreadyQueuedCallbacks() {
        let scheduler = FakeSleepScheduler()
        let countdown = SleepCountdown(scheduler: scheduler)
        var fires = 0
        countdown.onFire = { fires += 1 }
        countdown.start(minutes: 5)
        let stale = scheduler.callbacks[0].action
        countdown.start(minutes: 15)
        stale()
        XCTAssertEqual(countdown.remainingSeconds, 900)
        countdown.cancel()
        scheduler.callbacks.last?.action()
        XCTAssertNil(countdown.remainingSeconds)
        XCTAssertEqual(fires, 0)
    }

    func testOverdueWakeCallbackCancelsEvenBeforeWakeNotification() {
        let scheduler = FakeSleepScheduler()
        let countdown = SleepCountdown(scheduler: scheduler)
        var fires = 0
        countdown.onFire = { fires += 1 }
        countdown.start(minutes: 5)
        scheduler.now += 301
        scheduler.callbacks[0].action()
        XCTAssertNil(countdown.remainingSeconds)
        XCTAssertEqual(fires, 0)
    }

    func testInvalidPresetDoesNotReplaceExistingTimer() {
        let scheduler = FakeSleepScheduler()
        let countdown = SleepCountdown(scheduler: scheduler)
        countdown.start(minutes: 15)
        countdown.start(minutes: 1)
        XCTAssertEqual(countdown.remainingSeconds, 900)
    }

    func testTimerDoesNotWritePreferencesOrSettingsAndFiresOneSleepRequest() async {
        let (harness, viewModel) = await activeHarness()
        let journal = harness.store.journal
        let settingsWrites = harness.transport.writes
        viewModel.scheduleSleep(minutes: 5)
        XCTAssertNil(harness.store.sleepIntent)
        XCTAssertTrue(harness.preferences.writes.isEmpty)
        XCTAssertEqual(harness.store.journal, journal)
        harness.scheduler.advance(seconds: 300)
        await viewModel.sleepTask?.value
        XCTAssertEqual(harness.transport.sleepRequests.count, 1)
        XCTAssertEqual(harness.transport.writes, settingsWrites)
        XCTAssertEqual(harness.store.journal, journal)
        XCTAssertTrue(viewModel.sleepMessage?.contains("Physical sleep is not verified") == true)
    }

    func testOldToolDisablesOnlySleepAndSettingsStillRestore() async {
        let (harness, viewModel) = await activeHarness()
        harness.helperSetup.supportsSleep = false
        await viewModel.refreshHelperReadiness()
        XCTAssertTrue(viewModel.needsSleepAccessUpdate)
        XCTAssertFalse(viewModel.canSleep)
        XCTAssertTrue(viewModel.canToggleMaster)
        XCTAssertTrue(viewModel.canRestore)
        viewModel.sleepNow()
        XCTAssertTrue(harness.transport.sleepRequests.isEmpty)
        await viewModel.toggleMaster()
        XCTAssertEqual(viewModel.controlState, .off)
        XCTAssertEqual(harness.transport.values["powernap"], 1)
    }

    func testOffSetupSleepAndWakeCancelWithoutRearming() async {
        let (harness, viewModel) = await activeHarness()
        viewModel.scheduleSleep(minutes: 5)
        viewModel.systemWillSleep()
        XCTAssertNil(viewModel.sleepRemainingSeconds)
        viewModel.systemDidWake()
        harness.scheduler.advance(seconds: 301)
        XCTAssertTrue(harness.transport.sleepRequests.isEmpty)
        await harness.coordinator.waitUntilIdle()
        await viewModel.reconcile()
        viewModel.scheduleSleep(minutes: 15)
        viewModel.showHelperSetup = true
        XCTAssertNil(viewModel.sleepRemainingSeconds)
        viewModel.showHelperSetup = false
        viewModel.scheduleSleep(minutes: 30)
        await viewModel.toggleMaster()
        XCTAssertNil(viewModel.sleepRemainingSeconds)
        XCTAssertEqual(viewModel.controlState, .off)
        XCTAssertTrue(harness.transport.sleepRequests.isEmpty)
    }

    func testReadinessRefreshPreservesTimerButBlocksExpiryDuringCheck() async {
        let (harness, viewModel) = await activeHarness()
        viewModel.scheduleSleep(minutes: 5)
        await viewModel.refreshHelperReadiness()
        XCTAssertEqual(viewModel.sleepRemainingSeconds, 300)
        var resume: CheckedContinuation<HelperReadiness, Never>?
        harness.helperSetup.refreshHandler = { await withCheckedContinuation { resume = $0 } }
        let refresh = Task { await viewModel.refreshHelperReadiness() }
        while resume == nil { await Task.yield() }
        XCTAssertFalse(viewModel.canSleep)
        harness.scheduler.advance(seconds: 300)
        XCTAssertTrue(harness.transport.sleepRequests.isEmpty)
        XCTAssertNil(viewModel.sleepRemainingSeconds)
        resume?.resume(returning: .ready)
        await refresh.value
        XCTAssertNil(viewModel.sleepRemainingSeconds)
        XCTAssertTrue(harness.transport.sleepRequests.isEmpty)
    }

    func testCancelMessageIsNotOverwrittenByAnOlderSleepReceipt() async {
        let (harness, viewModel) = await activeHarness()
        viewModel.sleepNow()
        await viewModel.sleepTask?.value
        viewModel.scheduleSleep(minutes: 15)
        viewModel.cancelScheduledSleep()
        harness.coordinator.onChange?()
        XCTAssertEqual(viewModel.sleepMessage, "Sleep timer canceled.")
    }

    func testQuitAndReadinessLossCancelCountdown() async {
        let (harness, viewModel) = await activeHarness()
        viewModel.scheduleSleep(minutes: 5)
        harness.helperSetup.readiness = .notInstalled
        await viewModel.refreshHelperReadiness()
        XCTAssertNil(viewModel.sleepRemainingSeconds)
        harness.helperSetup.readiness = .ready
        await viewModel.refreshHelperReadiness()
        viewModel.scheduleSleep(minutes: 15)
        let quit = await viewModel.prepareToQuit()
        XCTAssertTrue(quit)
        XCTAssertNil(viewModel.sleepRemainingSeconds)
        XCTAssertTrue(harness.transport.sleepRequests.isEmpty)
    }

    func testCancellationAtEveryAdmissionAwaitPreventsIntentAndDispatch() async {
        for boundary in 0..<3 {
            let (harness, viewModel) = await activeHarness()
            var captures = 0
            harness.transport.beforeCapture = {
                captures += 1
                if (boundary == 0 && captures == 1) || (boundary == 2 && captures == 2) {
                    viewModel.cancelScheduledSleep()
                }
            }
            harness.transport.beforePrepareSleep = {
                if boundary == 1 { viewModel.cancelScheduledSleep() }
            }
            viewModel.sleepNow()
            await viewModel.sleepTask?.value
            XCTAssertTrue(harness.transport.sleepRequests.isEmpty, "boundary \(boundary)")
            XCTAssertNil(harness.store.sleepIntent, "boundary \(boundary)")
            XCTAssertTrue(viewModel.isActive)
        }
    }

    func testCapabilityLossDuringPreparationPreventsDispatch() async {
        let (harness, viewModel) = await activeHarness()
        harness.transport.beforePrepareSleep = {
            harness.helperSetup.supportsSleep = false
            await viewModel.refreshHelperReadiness()
        }
        viewModel.sleepNow()
        await viewModel.sleepTask?.value
        XCTAssertNil(harness.store.sleepIntent)
        XCTAssertTrue(harness.transport.sleepRequests.isEmpty)
    }

    func testDriftDuringPreparationRequiresRecoveryWithoutSleep() async {
        let (harness, viewModel) = await activeHarness()
        harness.transport.beforePrepareSleep = { harness.transport.values["powernap"] = 1 }
        viewModel.sleepNow()
        await viewModel.sleepTask?.value
        XCTAssertFalse(viewModel.isActive)
        XCTAssertNil(harness.store.sleepIntent)
        XCTAssertTrue(harness.transport.sleepRequests.isEmpty)
    }

    func testInitialIntentFailureNeverDispatchesAndPreservesSettingsJournal() async {
        let (harness, viewModel) = await activeHarness()
        let journal = harness.store.journal
        harness.store.sleepCommitError = RecoveryEvidenceError.invalid("Injected persistence failure")
        viewModel.sleepNow()
        await viewModel.sleepTask?.value
        XCTAssertTrue(harness.transport.sleepRequests.isEmpty)
        XCTAssertEqual(harness.store.journal, journal)
        XCTAssertTrue(viewModel.executionUncertain)
    }

    func testSentRequestCannotBeCanceledOrSentTwice() async {
        let (harness, viewModel) = await activeHarness()
        harness.transport.beforeSendSleep = {
            viewModel.cancelScheduledSleep()
            viewModel.sleepNow()
            viewModel.systemWillSleep()
        }
        viewModel.sleepNow()
        await viewModel.sleepTask?.value
        XCTAssertEqual(harness.transport.sleepRequests.count, 1)
        XCTAssertEqual(harness.store.sleepIntent?.acknowledged, true)
        XCTAssertTrue(viewModel.sleepMessage?.contains("Physical sleep is not verified") == true)
        XCTAssertFalse(viewModel.sleepMessage?.contains("canceled") == true)
    }

    func testLostReplyReconcilesBeforeRestoreWithoutReplayOrJournalReplacement() async {
        let (harness, viewModel) = await activeHarness()
        let successfulApply = harness.store.journal?.operation
        let originals = harness.store.journal?.cells.map(\.original)
        harness.transport.sleepOutcome = nil
        harness.transport.reconciledSleepOutcome = .childStoppedOutcomeUnknown(reason: "Owned child stopped without an exit receipt")
        viewModel.sleepNow()
        await viewModel.sleepTask?.value
        XCTAssertEqual(harness.store.journal?.operation, successfulApply)
        XCTAssertTrue(viewModel.executionUncertain)
        await harness.coordinator.restore()
        XCTAssertEqual(viewModel.controlState, .off)
        XCTAssertEqual(harness.transport.sleepRequests.count, 1)
        XCTAssertEqual(harness.transport.sleepReconciliations, 1)
        XCTAssertEqual(harness.store.sleepIntent?.acknowledged, true)
        XCTAssertEqual(harness.store.journal?.cells.map(\.original), originals)
        XCTAssertTrue(viewModel.sleepMessage?.contains("result is unknown") == true)
    }

    func testUnprovedChildRemainsFencedDespiteMatchingSettings() async {
        let (harness, viewModel) = await activeHarness()
        harness.transport.sleepOutcome = nil
        harness.transport.reconciledSleepOutcome = .intent
        viewModel.sleepNow()
        await viewModel.sleepTask?.value
        let writes = harness.transport.writes
        harness.transport.values["powernap"] = 1
        await harness.coordinator.restore()
        XCTAssertTrue(viewModel.executionUncertain)
        XCTAssertEqual(harness.transport.writes, writes)
        XCTAssertNil(harness.store.receipt)
        XCTAssertEqual(harness.transport.sleepAcks, 0)
    }

    func testTerminalSavedBeforeAckAndLostAckBlocksSettingsUntilRetry() async {
        let (harness, viewModel) = await activeHarness()
        harness.transport.beforeSleepAck = {
            XCTAssertNotNil(harness.store.sleepIntent?.terminal)
            XCTAssertEqual(harness.store.sleepEvents, ["intent", "terminal"])
        }
        harness.transport.sleepAckError = RecoveryEvidenceError.invalid("Lost ACK reply")
        viewModel.sleepNow()
        await viewModel.sleepTask?.value
        XCTAssertFalse(viewModel.executionUncertain)
        XCTAssertTrue(viewModel.sleepRequestInFlight)
        let writes = harness.transport.writes
        await harness.coordinator.restore()
        XCTAssertEqual(harness.transport.writes, writes)
        harness.transport.beforeSleepAck = nil
        harness.transport.sleepAckError = nil
        await harness.coordinator.restore()
        XCTAssertEqual(viewModel.controlState, .off)
        XCTAssertEqual(harness.transport.sleepRequests.count, 1)
        XCTAssertEqual(harness.transport.sleepReconciliations, 0)
    }

    func testRelaunchConsumesSavedSleepReceiptWithoutReplaying() async {
        let (harness, viewModel) = await activeHarness()
        harness.transport.sleepOutcome = nil
        viewModel.sleepNow()
        await viewModel.sleepTask?.value
        let relaunched = harness.makeViewModel()
        XCTAssertNil(relaunched.sleepRemainingSeconds)
        await relaunched.reconcile()
        XCTAssertTrue(relaunched.isActive)
        XCTAssertFalse(relaunched.sleepRequestInFlight)
        XCTAssertEqual(harness.transport.sleepRequests.count, 1)
        XCTAssertEqual(harness.store.sleepIntent?.acknowledged, true)
    }

    func testRealSleepStorageIsSeparateAndTerminalCompletionMarkerNeedsFreshProof() async throws {
        let directory = URL(fileURLWithPath: "/private/tmp/benzo-sleep-tests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var failCompletion = false
        let host = "99999999-9999-4999-8999-999999999999"
        let boot = "11111111-1111-4111-8111-111111111111"
        let store = DurableJournal(directory: directory, uid: getuid(), hostID: host, beforeBoundary: {
            if failCompletion, $0 == .completionMarkerRemove {
                failCompletion = false
                throw RecoveryEvidenceError.invalid("Injected completion marker failure")
            }
        })
        let transport = IntegrationRecoveryTransport()
        let coordinator = OperationCoordinator(store: store, transport: transport, uid: getuid(), hostID: host,
            bootID: { boot }, now: { Date(timeIntervalSince1970: 1000) }, legacyActive: { false }, legacyRule: { .noLegacyRule })
        await coordinator.apply(settings: [.disablePowerNap])
        let before = try store.loadJournal()
        failCompletion = true
        await coordinator.requestSleep { true }
        XCTAssertTrue(coordinator.executionUncertain)
        XCTAssertEqual(transport.sleepAcks, 0)
        XCTAssertNil(try store.loadSleepIntent()?.terminal)
        XCTAssertEqual(try store.loadJournal(), before)
        var unverified = try XCTUnwrap(store.loadSleepIntent())
        unverified.terminal = PowerSleepReceipt(request: unverified.request, outcome: .completed(exitStatus: 0))
        XCTAssertThrowsError(try store.commitSleepIntent(unverified))
        await coordinator.reconcile()
        XCTAssertTrue(coordinator.state.isActive)
        XCTAssertEqual(transport.sleepRequests.count, 1)
        XCTAssertEqual(transport.sleepReconciliations, 1)
        XCTAssertEqual(try store.loadSleepIntent()?.acknowledged, true)
        XCTAssertEqual(try store.loadJournal(), before)
        await coordinator.restore()
        XCTAssertEqual(coordinator.state, .off)
    }
}
