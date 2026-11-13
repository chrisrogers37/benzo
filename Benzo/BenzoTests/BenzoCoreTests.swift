import Foundation
import XCTest

@MainActor
final class BenzoCoreTests: XCTestCase {
    func testParsesValidSpaceSeparatedSettings() {
        let state = PMSetState(parsing: """
         hibernatemode        3
         standby             1
         powernap            0
        """)

        XCTAssertEqual(state.values, ["hibernatemode": "3", "standby": "1", "powernap": "0"])
        XCTAssertEqual(state.value(for: "standby"), "1")
        XCTAssertNil(state.value(for: "missing"))
    }

    func testBackupRoundTripUsesOnlyExplicitScratchURLAndClock() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = FakeClock()
        let store = BackupService(fileURL: directory.appendingPathComponent("originals.json"), clock: clock)
        let state = PMSetState(parsing: "hibernatemode 3\nstandby 1")

        XCTAssertEqual(store.evidencePresence(), .absent)
        XCTAssertFalse(store.hasBackup())
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        try store.save(state)
        let backup = try store.load()

        XCTAssertTrue(store.hasBackup())
        XCTAssertEqual(store.evidencePresence(), .present)
        XCTAssertEqual(backup.values, state.values)
        XCTAssertEqual(backup.capturedAt, clock.now)
    }

    func testBackupReadFailuresPropagateFromScratchStorage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("originals.json")
        let store = BackupService(fileURL: url, clock: FakeClock())

        XCTAssertThrowsError(try store.load())
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("invalid JSON".utf8).write(to: url)
        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertTrue(error is DecodingError)
        }
    }

    func testCorruptBackupEvidenceIsPresentAndUnchanged() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("originals.json")
        let bytes = Data("invalid JSON".utf8)
        try bytes.write(to: url)
        let store = BackupService(fileURL: url, clock: FakeClock())

        XCTAssertEqual(store.evidencePresence(), .present)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testAmbiguousBackupPathIsUnknownAndUnchanged() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let parentFile = directory.appendingPathComponent("not-a-directory")
        let bytes = Data("retain this evidence".utf8)
        try bytes.write(to: parentFile)
        let store = BackupService(fileURL: parentFile.appendingPathComponent("originals.json"), clock: FakeClock())

        guard case .unknown = store.evidencePresence() else {
            return XCTFail("An invalid parent path must not count as confirmed absence")
        }
        XCTAssertEqual(try Data(contentsOf: parentFile), bytes)
    }

    func testDanglingSymlinkAndDirectoryStillCountAsEvidence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let link = directory.appendingPathComponent("originals.json")
        let missingTarget = directory.appendingPathComponent("missing.json").path
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: missingTarget)

        XCTAssertEqual(BackupService(fileURL: link, clock: FakeClock()).evidencePresence(), .present)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), missingTarget)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingTarget))
        XCTAssertEqual(BackupService(fileURL: directory, clock: FakeClock()).evidencePresence(), .present)
    }

    func testNestedMissingBackupDirectoriesAreAbsentAndRemainUncreated() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("missing/nested/originals.json")
        let store = BackupService(fileURL: url, clock: FakeClock())

        XCTAssertEqual(store.evidencePresence(), .absent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testManualStartupDoesNotReadOrWriteAnyRecoveryBoundary() {
        let harness = FakeDependencies()
        harness.login.isEnabled = true
        harness.preferences.values[BenzoPreferenceKey.isActive] = true
        let viewModel = harness.makeViewModel()
        XCTAssertTrue(viewModel.launchAtLogin)
        XCTAssertEqual(viewModel.controlState, .checking)
        XCTAssertFalse(viewModel.isActive)
        XCTAssertEqual(harness.permissionObservations, 0)
        XCTAssertFalse(viewModel.showHelperSetup)
        XCTAssertTrue(harness.helperSetup.calls.isEmpty)
        XCTAssertEqual(harness.store.lockCalls, 0)
        XCTAssertEqual(harness.transport.captureCalls, 0)
        XCTAssertTrue(harness.transport.writes.isEmpty)
        XCTAssertTrue(harness.preferences.writes.isEmpty)
        XCTAssertTrue(harness.login.calls.isEmpty)
    }

    func testAutomaticStartupReconcilesReadOnlyAndDoesNotTrustSavedActive() async {
        let harness = FakeDependencies()
        harness.preferences.values[BenzoPreferenceKey.isActive] = true
        let viewModel = harness.makeViewModel(startupPolicy: .automatic)
        await viewModel.startupTask?.value
        guard case .recoveryRequired = viewModel.controlState else { return XCTFail("A saved Boolean is legacy evidence, never proof of active or Off") }
        XCTAssertFalse(viewModel.isActive)
        XCTAssertEqual(harness.permissionObservations, 0)
        XCTAssertEqual(harness.helperSetup.calls, ["refresh"])
        XCTAssertFalse(viewModel.showHelperSetup)
        XCTAssertTrue(harness.transport.writes.isEmpty)
        XCTAssertTrue(harness.preferences.writes.isEmpty)
        XCTAssertTrue(harness.login.calls.isEmpty)
    }

    func testHelperRefreshOnlyUpdatesReadinessAndPreservesRecoveryAndNavigation() async {
        let harness = FakeDependencies()
        let viewModel = harness.makeViewModel()
        let states = viewModel.settingStates
        viewModel.errorMessage = "Preserve unrelated error"
        var stateChanges = 0
        viewModel.onStateChange = { _ in stateChanges += 1 }
        for readiness in [HelperReadiness.notInstalled, .requiresApproval, .differentAccount] {
            harness.helperSetup.readiness = readiness
            await viewModel.refreshHelperReadiness()
            XCTAssertEqual(viewModel.helperReadiness, readiness)
        }
        viewModel.showHelperSetup = true
        viewModel.showHelperSetup = false
        XCTAssertEqual(viewModel.settingStates, states)
        XCTAssertEqual(viewModel.errorMessage, "Preserve unrelated error")
        XCTAssertEqual(stateChanges, 0)
        XCTAssertEqual(harness.permissionObservations, 0)
        XCTAssertEqual(harness.helperSetup.calls, ["refresh", "refresh", "refresh"])
        XCTAssertTrue(harness.preferences.writes.isEmpty)
        XCTAssertTrue(harness.transport.writes.isEmpty)
        XCTAssertEqual(harness.store.lockCalls, 0)
    }

    func testSetupRequiresOSApprovalAndAccountAuthorizationBeforeWrites() async {
        let harness = FakeDependencies()
        harness.helperSetup.readiness = .notInstalled
        let viewModel = harness.makeViewModel()
        await viewModel.reconcile()
        XCTAssertEqual(viewModel.controlState, .off)
        XCTAssertFalse(viewModel.canToggleMaster)
        await viewModel.toggleMaster()
        XCTAssertNil(harness.store.journal)
        await viewModel.registerHelper()
        XCTAssertEqual(viewModel.helperReadiness, .requiresApproval)
        viewModel.openHelperApprovalSettings()
        XCTAssertEqual(viewModel.helperReadiness, .requiresApproval)
        await viewModel.authorizeCurrentAccount()
        XCTAssertFalse(harness.helperSetup.calls.contains("authorize"))

        harness.helperSetup.readiness = .needsOwnerAuthorization
        await viewModel.refreshHelperReadiness()
        await viewModel.authorizeCurrentAccount()
        XCTAssertEqual(viewModel.helperReadiness, .ready)
        XCTAssertTrue(viewModel.canToggleMaster)
        XCTAssertEqual(harness.helperSetup.calls, ["refresh", "register", "refresh", "openSettings", "refresh", "authorize", "refresh"])
        XCTAssertTrue(harness.transport.writes.isEmpty)
        XCTAssertNil(harness.store.journal)
    }

    func testSetupSuccessDoesNotTreatRegistrationAsReadiness() async {
        let harness = FakeDependencies()
        harness.helperSetup.readiness = .notInstalled
        let viewModel = harness.makeViewModel()
        await viewModel.reconcile()
        harness.helperSetup.registrationResult = .ready
        harness.helperSetup.refreshHandler = { .requiresApproval }
        await viewModel.registerHelper()
        XCTAssertEqual(viewModel.helperReadiness, .requiresApproval)
        XCTAssertFalse(viewModel.canToggleMaster)
        XCTAssertTrue(harness.transport.writes.isEmpty)
    }

    func testSetupCancellationAndDenialRemainDistinctAfterRefresh() async {
        for message in ["Authorization was cancelled.", "Authorization was denied."] {
            let harness = FakeDependencies()
            harness.helperSetup.readiness = .needsOwnerAuthorization
            harness.helperSetup.error = NSError(domain: "SetupTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
            let viewModel = harness.makeViewModel()
            await viewModel.reconcile()
            await viewModel.authorizeCurrentAccount()
            XCTAssertEqual(viewModel.helperSetupError, message)
            XCTAssertEqual(viewModel.helperReadiness, .needsOwnerAuthorization)
            XCTAssertEqual(harness.helperSetup.calls, ["refresh", "authorize", "refresh"])
            XCTAssertFalse(viewModel.isPerformingHelperSetup)
            XCTAssertTrue(harness.transport.writes.isEmpty)
        }
    }

    func testHelperReplacementIsExplicitAndOnlyAvailableWhenOff() async {
        let harness = FakeDependencies()
        harness.helperSetup.readiness = .unavailable(.incompatible)
        let viewModel = harness.makeViewModel(startupPolicy: .automatic)
        await viewModel.startupTask?.value
        XCTAssertEqual(viewModel.controlState, .off)
        XCTAssertTrue(viewModel.canReplaceHelper)
        XCTAssertEqual(harness.helperSetup.calls, ["refresh"])
        await viewModel.replaceHelper()
        XCTAssertEqual(harness.helperSetup.calls, ["refresh", "replace", "refresh"])
        XCTAssertEqual(viewModel.helperReadiness, .ready)
        XCTAssertFalse(viewModel.canReplaceHelper)
        XCTAssertTrue(harness.transport.writes.isEmpty)
        XCTAssertNil(harness.store.journal)
    }

    func testHelperReplacementDoesNotUseReturnedSuccessAsReadiness() async {
        let harness = FakeDependencies()
        harness.helperSetup.readiness = .unavailable(.incompatible)
        let viewModel = harness.makeViewModel()
        await viewModel.reconcile()
        harness.helperSetup.refreshHandler = { .requiresApproval }
        await viewModel.replaceHelper()
        XCTAssertEqual(viewModel.helperReadiness, .requiresApproval)
        XCTAssertFalse(viewModel.hasHelperAccess)
        XCTAssertTrue(harness.transport.writes.isEmpty)
    }

    func testHelperReplacementIsBlockedDuringActiveSessionAndRecovery() async {
        let harness = FakeDependencies()
        let viewModel = harness.makeViewModel()
        await viewModel.reconcile()
        await viewModel.toggleMaster()
        harness.helperSetup.readiness = .unavailable(.incompatible)
        await viewModel.refreshHelperReadiness()
        XCTAssertFalse(viewModel.canReplaceHelper)
        let journal = harness.store.journal
        let fence = harness.store.fence
        await viewModel.replaceHelper()
        XCTAssertFalse(harness.helperSetup.calls.contains("replace"))
        XCTAssertEqual(harness.store.journal, journal)
        XCTAssertEqual(harness.store.fence, fence)

        harness.transport.values["hibernatemode"] = 0
        await viewModel.reconcile()
        guard case .recoveryRequired = viewModel.controlState else { return XCTFail("Expected recovery") }
        XCTAssertFalse(viewModel.canReplaceHelper)
        let recoveryJournal = harness.store.journal
        await viewModel.replaceHelper()
        XCTAssertFalse(harness.helperSetup.calls.contains("replace"))
        XCTAssertEqual(harness.store.journal, recoveryJournal)
    }

    func testHelperReplacementIsBlockedInLegacyRecoveryWithoutCurrentSession() async {
        let harness = FakeDependencies()
        harness.store.legacy = Data("preserve legacy evidence".utf8)
        harness.helperSetup.readiness = .unavailable(.incompatible)
        let viewModel = harness.makeViewModel()
        await viewModel.reconcile()
        XCTAssertFalse(viewModel.hasSession)
        XCTAssertFalse(viewModel.canReplaceHelper)
        await viewModel.replaceHelper()
        XCTAssertFalse(harness.helperSetup.calls.contains("replace"))
        XCTAssertEqual(harness.store.legacy, Data("preserve legacy evidence".utf8))
    }

    func testHelperReplacementCannotBeStartedTwiceWhileSetupIsPending() async {
        let harness = FakeDependencies()
        harness.helperSetup.readiness = .unavailable(.incompatible)
        let viewModel = harness.makeViewModel()
        await viewModel.reconcile()
        var resume: CheckedContinuation<HelperReadiness, Never>?
        harness.helperSetup.replacementHandler = { await withCheckedContinuation { resume = $0 } }
        let replacement = Task { await viewModel.replaceHelper() }
        while resume == nil { await Task.yield() }
        XCTAssertTrue(viewModel.isPerformingHelperSetup)
        XCTAssertFalse(viewModel.canReplaceHelper)
        harness.helperSetup.readiness = .ready
        await viewModel.refreshHelperReadiness()
        XCTAssertEqual(viewModel.helperReadiness, .ready)
        XCTAssertFalse(viewModel.hasHelperAccess)
        XCTAssertFalse(viewModel.canToggleMaster)
        await viewModel.toggleMaster()
        let mayQuit = await viewModel.prepareToQuit()
        XCTAssertFalse(mayQuit)
        XCTAssertEqual(viewModel.errorMessage, BenzoViewModel.helperSetupInProgressReason)
        await viewModel.replaceHelper()
        XCTAssertEqual(harness.helperSetup.calls.filter { $0 == "replace" }.count, 1)
        resume?.resume(returning: .ready)
        await replacement.value
        XCTAssertFalse(viewModel.isPerformingHelperSetup)
        XCTAssertEqual(viewModel.helperReadiness, .ready)
        XCTAssertTrue(harness.transport.writes.isEmpty)
    }

    func testHelperRemovalIsExplicitAndRetainsResolvedRecoveryEvidence() async {
        for readiness in [HelperReadiness.ready, .unavailable(.incompatible)] {
            let harness = FakeDependencies()
            let viewModel = harness.makeViewModel()
            await viewModel.reconcile()
            await viewModel.toggleMaster()
            await viewModel.revertToDefaults()
            XCTAssertEqual(viewModel.controlState, .off)
            let journal = harness.store.journal
            let receipt = harness.store.receipt
            let fence = harness.store.fence
            let writes = harness.transport.writes
            harness.helperSetup.readiness = readiness
            await viewModel.refreshHelperReadiness()
            XCTAssertTrue(viewModel.canRemoveHelper)
            XCTAssertFalse(harness.helperSetup.calls.contains("remove"))
            await viewModel.removeHelper()
            XCTAssertEqual(Array(harness.helperSetup.calls.suffix(2)), ["remove", "refresh"])
            XCTAssertEqual(viewModel.helperReadiness, .notInstalled)
            XCTAssertFalse(viewModel.canRemoveHelper)
            XCTAssertEqual(harness.store.journal, journal)
            XCTAssertEqual(harness.store.receipt, receipt)
            XCTAssertEqual(harness.store.fence, fence)
            XCTAssertEqual(harness.transport.writes, writes)
        }
    }

    func testHelperRemovalRefusesActiveSessionConflictAndExecutionUncertainty() async {
        let harness = FakeDependencies()
        let viewModel = harness.makeViewModel()
        await viewModel.reconcile()
        await viewModel.toggleMaster()
        XCTAssertFalse(viewModel.canRemoveHelper)
        await viewModel.removeHelper()
        XCTAssertFalse(harness.helperSetup.calls.contains("remove"))
        harness.transport.values["hibernatemode"] = 0
        await viewModel.reconcile()
        XCTAssertFalse(viewModel.conflicts.isEmpty)
        XCTAssertFalse(viewModel.canRemoveHelper)
        await viewModel.removeHelper()
        XCTAssertFalse(harness.helperSetup.calls.contains("remove"))

        let uncertain = FakeDependencies()
        let uncertainViewModel = uncertain.makeViewModel()
        await uncertainViewModel.reconcile()
        uncertain.transport.writeOutcome = .uncertain("Execution did not settle.")
        await uncertainViewModel.toggleMaster()
        XCTAssertTrue(uncertainViewModel.executionUncertain)
        XCTAssertFalse(uncertainViewModel.canRemoveHelper)
        let journal = uncertain.store.journal
        let fence = uncertain.store.fence
        await uncertainViewModel.removeHelper()
        XCTAssertFalse(uncertain.helperSetup.calls.contains("remove"))
        XCTAssertEqual(uncertain.store.journal, journal)
        XCTAssertEqual(uncertain.store.fence, fence)
    }

    func testFailedHelperRemovalRetainsEvidenceAndSurfacesTheError() async {
        let harness = FakeDependencies()
        let viewModel = harness.makeViewModel()
        await viewModel.reconcile()
        await viewModel.toggleMaster()
        await viewModel.revertToDefaults()
        let journal = harness.store.journal
        let receipt = harness.store.receipt
        let fence = harness.store.fence
        let writes = harness.transport.writes
        harness.helperSetup.error = NSError(domain: "SetupTest", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Helper removal was denied."])
        await viewModel.removeHelper()
        XCTAssertEqual(viewModel.helperSetupError, "Helper removal was denied.")
        XCTAssertEqual(viewModel.helperReadiness, .ready)
        XCTAssertEqual(harness.store.journal, journal)
        XCTAssertEqual(harness.store.receipt, receipt)
        XCTAssertEqual(harness.store.fence, fence)
        XCTAssertEqual(harness.transport.writes, writes)
    }

    func testPendingHelperRemovalBlocksDuplicateSetupWritesAndOrdinaryQuit() async {
        let harness = FakeDependencies()
        let viewModel = harness.makeViewModel()
        await viewModel.reconcile()
        var resume: CheckedContinuation<HelperReadiness, Never>?
        harness.helperSetup.removalHandler = { await withCheckedContinuation { resume = $0 } }
        let removal = Task { await viewModel.removeHelper() }
        while resume == nil { await Task.yield() }
        XCTAssertTrue(viewModel.isPerformingHelperSetup)
        XCTAssertFalse(viewModel.canRemoveHelper)
        XCTAssertFalse(viewModel.canToggleMaster)
        await viewModel.toggleMaster()
        await viewModel.removeHelper()
        let mayQuit = await viewModel.prepareToQuit()
        XCTAssertFalse(mayQuit)
        XCTAssertEqual(viewModel.errorMessage, BenzoViewModel.helperSetupInProgressReason)
        XCTAssertEqual(harness.helperSetup.calls.filter { $0 == "remove" }.count, 1)
        XCTAssertTrue(harness.transport.writes.isEmpty)
        resume?.resume(returning: .notInstalled)
        await removal.value
        XCTAssertFalse(viewModel.isPerformingHelperSetup)
        XCTAssertEqual(viewModel.helperReadiness, .notInstalled)
    }

    func testSuccessfulQuitKeepsMutationAdmissionClosedUntilApplicationTerminates() async {
        let harness = FakeDependencies()
        let viewModel = harness.makeViewModel()
        await viewModel.reconcile()
        await viewModel.toggleMaster()
        harness.helperSetup.refreshHandler = {
            XCTFail("Successful quit must not reopen an asynchronous helper refresh window")
            return .ready
        }

        let mayQuit = await viewModel.prepareToQuit()
        XCTAssertTrue(mayQuit)
        XCTAssertTrue(viewModel.isPreparingToQuit)
        XCTAssertEqual(viewModel.controlState, .off)
        XCTAssertFalse(viewModel.hasSession)
        XCTAssertFalse(viewModel.canToggleMaster)
        XCTAssertFalse(viewModel.canRestore)
        XCTAssertFalse(viewModel.canRemoveHelper)
        let writes = harness.transport.writes
        let journal = harness.store.journal
        let receipt = harness.store.receipt
        let selection = viewModel.settingStates
        let preferenceWrites = harness.preferences.writes
        let setupCalls = harness.helperSetup.calls

        // AppKit has not yet replied to the termination request. No new action
        // may invalidate the successful restoration result in this interval.
        await viewModel.toggleMaster()
        viewModel.toggleSetting(.disablePowerNap)
        await viewModel.revertToDefaults()
        await viewModel.removeHelper()
        viewModel.launchAtLogin = true
        XCTAssertFalse(viewModel.launchAtLogin)
        XCTAssertEqual(harness.transport.writes, writes)
        XCTAssertEqual(harness.store.journal, journal)
        XCTAssertEqual(harness.store.receipt, receipt)
        XCTAssertEqual(viewModel.settingStates, selection)
        XCTAssertEqual(harness.preferences.writes, preferenceWrites)
        XCTAssertEqual(harness.helperSetup.calls, setupCalls)
        XCTAssertTrue(harness.login.calls.isEmpty)
        XCTAssertEqual(viewModel.controlState, .off)
        XCTAssertFalse(viewModel.hasSession)
    }

    func testPendingQuitBlocksSetupAndSelectionAcrossHelperReadinessStates() async {
        for readiness in [HelperReadiness.ready, .notInstalled, .needsOwnerAuthorization,
                          .requiresApproval, .unavailable(.incompatible)] {
            let harness = FakeDependencies()
            harness.helperSetup.readiness = readiness
            let viewModel = harness.makeViewModel()
            await viewModel.reconcile()
            let started = expectation(description: "Quit capture started: \(readiness)")
            var resume: CheckedContinuation<Void, Never>?
            harness.transport.beforeCapture = {
                await withCheckedContinuation { resume = $0; started.fulfill() }
            }
            let pendingQuit = Task { await viewModel.prepareToQuit() }
            await fulfillment(of: [started], timeout: 1)
            guard let resume else { return XCTFail("Quit did not reach its injected capture") }
            XCTAssertTrue(viewModel.isPreparingToQuit)
            XCTAssertFalse(viewModel.canToggleMaster)
            XCTAssertFalse(viewModel.canRestore)
            XCTAssertFalse(viewModel.canReplaceHelper)
            XCTAssertFalse(viewModel.canRemoveHelper)
            let selection = viewModel.settingStates
            let setupCalls = harness.helperSetup.calls
            let preferenceWrites = harness.preferences.writes

            await viewModel.toggleMaster()
            viewModel.toggleSetting(.disablePowerNap)
            await viewModel.registerHelper()
            await viewModel.authorizeCurrentAccount()
            await viewModel.replaceHelper()
            await viewModel.removeHelper()
            viewModel.openHelperApprovalSettings()
            viewModel.launchAtLogin = true
            XCTAssertFalse(viewModel.launchAtLogin)
            XCTAssertEqual(viewModel.settingStates, selection)
            XCTAssertEqual(harness.preferences.writes, preferenceWrites)
            XCTAssertEqual(harness.helperSetup.calls, setupCalls)
            XCTAssertFalse(viewModel.isPerformingHelperSetup)
            XCTAssertTrue(harness.transport.writes.isEmpty)
            XCTAssertTrue(harness.login.calls.isEmpty)

            harness.transport.beforeCapture = nil
            resume.resume()
            let mayQuit = await pendingQuit.value
            XCTAssertTrue(mayQuit)
            XCTAssertTrue(viewModel.isPreparingToQuit)
            XCTAssertEqual(viewModel.controlState, .off)
            XCTAssertFalse(viewModel.hasSession)
        }
    }

    func testFailedQuitReleasesAdmissionSoRestorationCanBeRetried() async {
        let harness = FakeDependencies()
        let viewModel = harness.makeViewModel()
        await viewModel.reconcile()
        await viewModel.toggleMaster()
        harness.transport.captureError = NSError(domain: "QuitTest", code: 1)
        let firstAttempt = await viewModel.prepareToQuit()
        XCTAssertFalse(firstAttempt)
        XCTAssertFalse(viewModel.isPreparingToQuit)
        XCTAssertTrue(viewModel.hasSession)
        XCTAssertTrue(viewModel.hasHelperAccess)
        XCTAssertNotNil(harness.store.journal)

        harness.transport.captureError = nil
        let retry = await viewModel.prepareToQuit()
        XCTAssertTrue(retry)
        XCTAssertTrue(viewModel.isPreparingToQuit)
        XCTAssertEqual(viewModel.controlState, .off)
        XCTAssertFalse(viewModel.hasSession)
        XCTAssertNotNil(harness.store.receipt)
    }

    func testRefreshingReadyHelperKeepsLastObservationUntilNewStatusArrives() async {
        let harness = FakeDependencies()
        let viewModel = harness.makeViewModel()
        await viewModel.reconcile()
        var resume: CheckedContinuation<HelperReadiness, Never>?
        harness.helperSetup.refreshHandler = { await withCheckedContinuation { resume = $0 } }
        let refresh = Task { await viewModel.refreshHelperReadiness() }
        while resume == nil { await Task.yield() }
        XCTAssertTrue(viewModel.isRefreshingHelper)
        XCTAssertTrue(viewModel.hasHelperAccess)
        XCTAssertTrue(viewModel.canToggleMaster)
        resume?.resume(returning: .unavailable(.connection))
        await refresh.value
        XCTAssertFalse(viewModel.isRefreshingHelper)
        XCTAssertFalse(viewModel.hasHelperAccess)
    }

    func testUnavailableHelperPreservesActiveRecoveryAndBlocksRestoreAndQuit() async {
        for readiness in [HelperReadiness.notInstalled, .requiresApproval, .needsOwnerAuthorization, .differentAccount,
                          .unavailable(.connection), .unavailable(.incompatible), .unavailable(.signingUnavailable), .unavailable(.executionUncertain)] {
            let harness = FakeDependencies()
            let viewModel = harness.makeViewModel()
            await viewModel.reconcile()
            await viewModel.toggleMaster()
            let journal = harness.store.journal
            let fence = harness.store.fence
            let writes = harness.transport.writes
            let commits = harness.store.journalCommits
            harness.helperSetup.readiness = readiness
            await viewModel.refreshHelperReadiness()
            XCTAssertTrue(viewModel.isActive)
            XCTAssertTrue(viewModel.hasSession)
            XCTAssertFalse(viewModel.canRestore)
            XCTAssertFalse(viewModel.canToggleMaster)
            await viewModel.toggleMaster()
            await viewModel.revertToDefaults()
            let mayQuit = await viewModel.prepareToQuit()
            XCTAssertFalse(mayQuit)
            XCTAssertEqual(viewModel.errorMessage, BenzoViewModel.helperRecoveryReason)
            XCTAssertEqual(harness.store.journal, journal)
            XCTAssertEqual(harness.store.fence, fence)
            XCTAssertEqual(harness.store.journalCommits, commits)
            XCTAssertEqual(harness.transport.writes, writes)
            viewModel.showHelperSetup = true
            viewModel.showHelperSetup = false
            XCTAssertTrue(viewModel.hasSession)
        }
    }

    func testOperationFinishingDuringHelperRefreshQueuesASettledStatusRead() async {
        let harness = FakeDependencies()
        let viewModel = harness.makeViewModel()
        await viewModel.reconcile()
        var resume: CheckedContinuation<HelperReadiness, Never>?
        var reads = 0
        harness.helperSetup.refreshHandler = {
            reads += 1
            if reads == 1 { return await withCheckedContinuation { resume = $0 } }
            return .ready
        }
        let refresh = Task { await viewModel.refreshHelperReadiness() }
        while resume == nil { await Task.yield() }
        await viewModel.toggleMaster()
        XCTAssertTrue(viewModel.isActive)
        resume?.resume(returning: .unavailable(.executionUncertain))
        await refresh.value
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(viewModel.helperReadiness, .ready)
        XCTAssertTrue(viewModel.canRestore)
    }

    func testMissingHelperBlocksConflictRestoreWithoutClearingEvidence() async {
        let harness = FakeDependencies()
        let viewModel = harness.makeViewModel()
        await viewModel.reconcile()
        await viewModel.toggleMaster()
        harness.transport.values["hibernatemode"] = 0
        harness.helperSetup.readiness = .differentAccount
        await viewModel.reconcile()
        guard let conflict = viewModel.conflicts.first else { return XCTFail("Expected conflict") }
        let journal = harness.store.journal
        let writes = harness.transport.writes
        await viewModel.resolveConflict(conflict, choice: .restoreOriginal)
        XCTAssertEqual(viewModel.conflicts, [conflict])
        XCTAssertEqual(harness.store.journal, journal)
        XCTAssertEqual(harness.transport.writes, writes)
    }

    func testSleepNowRemainsDisabledWithoutCaptureWriteOrContinuation() {
        let harness = FakeDependencies()
        let viewModel = harness.makeViewModel()
        viewModel.sleepNow()
        XCTAssertEqual(viewModel.errorMessage, BenzoViewModel.sleepUnavailableReason)
        XCTAssertEqual(harness.transport.captureCalls, 0)
        XCTAssertTrue(harness.transport.writes.isEmpty)
        XCTAssertTrue(harness.preferences.writes.isEmpty)
        XCTAssertTrue(harness.mainQueue.isEmpty)
        XCTAssertTrue(harness.backgroundQueue.isEmpty)
    }

    func testCheckingAndLegacyRecoveryFreezePreferences() async {
        let harness = FakeDependencies()
        harness.store.legacy = Data("untrusted legacy bytes".utf8)
        let viewModel = harness.makeViewModel()
        let states = viewModel.settingStates
        viewModel.toggleSetting(.hibernateMode)
        XCTAssertEqual(viewModel.settingStates, states)
        XCTAssertTrue(harness.preferences.writes.isEmpty)
        await viewModel.reconcile()
        guard case .recoveryRequired = viewModel.controlState else { return XCTFail("Legacy evidence requires recovery") }
        viewModel.toggleSetting(.hibernateMode)
        await viewModel.revertToDefaults()
        XCTAssertEqual(viewModel.settingStates, states)
        XCTAssertTrue(harness.preferences.writes.isEmpty)
        XCTAssertTrue(harness.transport.writes.isEmpty)
        XCTAssertEqual(harness.store.legacy, Data("untrusted legacy bytes".utf8))
    }

    func testOffSelectionEditRechecksFreshProvenanceBeforePersistence() async {
        let harness = FakeDependencies()
        let viewModel = harness.makeViewModel()
        await viewModel.reconcile()
        XCTAssertEqual(viewModel.controlState, .off)
        viewModel.toggleSetting(.disableTcpKeepAlive)
        XCTAssertEqual(viewModel.settingStates[.disableTcpKeepAlive], true)
        XCTAssertEqual(harness.preferences.writes, [BenzoPreferenceKey.settingStates])
        let states = viewModel.settingStates
        harness.store.legacy = Data("new evidence".utf8)
        viewModel.toggleSetting(.disableTcpKeepAlive)
        XCTAssertEqual(viewModel.settingStates, states)
        XCTAssertEqual(harness.preferences.writes, [BenzoPreferenceKey.settingStates])
        XCTAssertTrue(harness.transport.writes.isEmpty)
    }

    func testUnavailableControlsAreUncheckedAndCannotPersistAnEdit() async {
        let harness = FakeDependencies()
        harness.transport.values.removeValue(forKey: "hibernatemode")
        harness.transport.values.removeValue(forKey: "autopoweroff")
        harness.transport.values.removeValue(forKey: "proximitywake")
        let viewModel = harness.makeViewModel()
        await viewModel.reconcile()
        XCTAssertFalse(viewModel.isSelected(.hibernateMode))
        XCTAssertFalse(viewModel.isSelected(.disableProximityWake))
        XCTAssertEqual(viewModel.activeCount, 2)
        viewModel.toggleSetting(.hibernateMode)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(harness.preferences.writes.isEmpty)
        await viewModel.toggleMaster()
        XCTAssertTrue(viewModel.isActive)
        XCTAssertEqual(Set(harness.transport.writes.map { $0.cell.key.rawValue }), Set(["powernap", "womp"]))
    }

    func testSystemDefaultsRequiresResolvingConflictsFirst() async {
        let harness = FakeDependencies()
        let viewModel = harness.makeViewModel()
        await viewModel.reconcile()
        await viewModel.toggleMaster()
        XCTAssertTrue(viewModel.canRestore)
        harness.transport.values["hibernatemode"] = 0
        await viewModel.reconcile()
        XCTAssertFalse(viewModel.canRestore)
        XCTAssertEqual(viewModel.conflicts.count, 1)
        guard let conflict = viewModel.conflicts.first else { return }
        await viewModel.resolveConflict(conflict, choice: .keepCurrent)
        XCTAssertTrue(viewModel.canRestore)
    }

    func testActiveSessionFreezesSelectionsAndSystemDefaultsRestoresCapturedValues() async {
        let harness = FakeDependencies()
        let viewModel = harness.makeViewModel()
        await viewModel.reconcile()
        let originalValues = harness.transport.values
        await viewModel.toggleMaster()
        XCTAssertTrue(viewModel.isActive)
        let states = viewModel.settingStates
        viewModel.toggleSetting(.disableTcpKeepAlive)
        XCTAssertEqual(viewModel.settingStates, states)
        XCTAssertTrue(harness.preferences.writes.isEmpty)
        XCTAssertNotNil(viewModel.capturedAt)
        await viewModel.revertToDefaults()
        XCTAssertEqual(viewModel.controlState, .off)
        XCTAssertEqual(harness.transport.values, originalValues)
        XCTAssertNotNil(harness.store.receipt)
        XCTAssertFalse(harness.preferences.writes.contains(BenzoPreferenceKey.isActive))
    }

    func testFailedRestorationCannotApproveQuitAndPreservesEvidence() async {
        let harness = FakeDependencies()
        let viewModel = harness.makeViewModel()
        await viewModel.reconcile()
        await viewModel.toggleMaster()
        let originalJournal = harness.store.journal
        harness.transport.writeOutcome = .uncertain("Fixture authorization result is uncertain")
        let shouldQuit = await viewModel.prepareToQuit()
        XCTAssertFalse(shouldQuit)
        XCTAssertTrue(viewModel.executionUncertain)
        guard case .recoveryRequired = viewModel.controlState else { return XCTFail("Failed restore must remain recovery") }
        XCTAssertEqual(harness.store.journal?.sessionID, originalJournal?.sessionID)
        XCTAssertEqual(harness.terminationCalls, 0)
        let writes = harness.transport.writes.count
        let retry = await viewModel.prepareToQuit()
        XCTAssertFalse(retry)
        XCTAssertEqual(harness.transport.writes.count, writes)
        viewModel.quit()
        XCTAssertEqual(harness.terminationCalls, 1, "The menu requests AppKit termination; it does not discard evidence")
        XCTAssertNotNil(harness.store.journal)
        XCTAssertNotNil(harness.store.fence)
    }

    func testLoginSetterReachesOnlyInjectedRegisterAndUnregister() {
        let harness = FakeDependencies()
        let viewModel = harness.makeViewModel()

        viewModel.launchAtLogin = true
        viewModel.launchAtLogin = false

        XCTAssertEqual(harness.login.calls, ["register", "unregister"])
        XCTAssertTrue(harness.transport.writes.isEmpty)
    }

    func testLoginErrorsPropagateToViewModel() {
        let harness = FakeDependencies()
        harness.login.error = ShellError.executionFailed("fake login denied")
        let viewModel = harness.makeViewModel()

        viewModel.launchAtLogin = true
        XCTAssertEqual(viewModel.errorMessage, "Failed to update launch at login: fake login denied")
        viewModel.errorMessage = nil
        viewModel.launchAtLogin = false
        XCTAssertEqual(viewModel.errorMessage, "Failed to update launch at login: fake login denied")
        XCTAssertEqual(harness.login.calls, ["register", "unregister"])
    }

    func testDiagnosticsAndTerminationUseInjectedCallbacks() async {
        let harness = FakeDependencies()
        let viewModel = harness.makeViewModel()

        viewModel.loadDiagnostics()
        XCTAssertTrue(viewModel.isLoadingDiagnostics)
        XCTAssertEqual(harness.diagnosticCalls, 0)
        await harness.runBackgroundQueue()
        XCTAssertEqual(harness.diagnosticCalls, 3)
        XCTAssertTrue(viewModel.isLoadingDiagnostics)
        harness.runMainQueue()
        XCTAssertEqual(harness.diagnosticCalls, 3)
        XCTAssertFalse(viewModel.isLoadingDiagnostics)
        viewModel.quit()
        XCTAssertEqual(harness.terminationCalls, 1)
        XCTAssertTrue(harness.transport.writes.isEmpty)
    }

    func testDiagnosticReaderPreservesFailureTimeoutAndIncompleteCapture() async {
        let reader = FakeReadCommandRunner()
        let service = DiagnosticService(reader: reader)
        for termination in [Termination.exited(1), .timedOut, .cancelled, .signaled(15), .launchFailed("fixture")] {
            reader.outcome = CommandOutcome(stdout: Data("{\"SPUSBDataType\":[]}".utf8), stderr: Data("fixture error".utf8), termination: termination, outputComplete: true, outputTruncated: false, directChildStopped: true)
            let result = await service.fetchUSBDevices()
            guard case .failure(.commandFailed(let outcome)) = result else { return XCTFail("Failed capture must not become empty success") }
            XCTAssertEqual(outcome.termination, termination)
            XCTAssertEqual(outcome.stderr, Data("fixture error".utf8))
        }
        for (complete, truncated) in [(false, false), (true, true)] {
            reader.outcome = CommandOutcome(stdout: Data("{\"SPUSBDataType\":[]}".utf8), stderr: Data(), termination: .exited(0), outputComplete: complete, outputTruncated: truncated, directChildStopped: true)
            let result = await service.fetchUSBDevices()
            guard case .failure(.incompleteCapture(let outcome)) = result else { return XCTFail("Partial capture must not become empty success") }
            XCTAssertEqual(outcome.outputComplete, complete)
            XCTAssertEqual(outcome.outputTruncated, truncated)
        }
    }

    func testDiagnosticReaderUsesOnlyFixedInjectedReadsAndRejectsInvalidUTF8() async throws {
        let reader = FakeReadCommandRunner()
        let service = DiagnosticService(reader: reader)
        reader.outcome = completeOutcome("2026-11-02 12:00:00 -0500 Assertions PID 42 Created UserIsActive")
        let sleep = try await service.fetchSleepData().get()
        XCTAssertTrue(sleep.sessions.isEmpty)
        reader.outcome = completeOutcome("{\"SPUSBDataType\":[]}")
        let usb = try await service.fetchUSBDevices().get()
        XCTAssertTrue(usb.isEmpty)
        reader.outcome = completeOutcome("hibernatemode 3")
        let settings = try await service.readObservedSettings().get()
        XCTAssertEqual(settings.first?.actualValue, "3")
        XCTAssertEqual(reader.calls, [.sleepLog, .usbDevices, .currentSettings])
        reader.outcome = CommandOutcome(stdout: Data([0xff]), stderr: Data(), termination: .exited(0), outputComplete: true, outputTruncated: false, directChildStopped: true)
        guard case .failure(.malformedFormat) = await service.readObservedSettings() else { return XCTFail("Invalid encoding is unavailable") }
    }

    func testUSBSupportedEmptyAndNestedDeviceFixtures() throws {
        XCTAssertTrue(try DiagnosticService.parseUSBDevices("{\"SPUSBDataType\":[]}").get().isEmpty)
        XCTAssertTrue(try DiagnosticService.parseUSBDevices("{\"SPUSBDataType\":[{\"_name\":\"USB Bus\",\"_items\":[]}]}").get().isEmpty)
        let devices = try DiagnosticService.parseUSBDevices("""
        {"SPUSBDataType":[{"_name":"USB Bus","_items":[
          {"_name":"Hub","vendor_id":"0x1234","_items":[
            {"_name":"Keyboard","manufacturer":"Fixture","bus_power_used":"100"}
          ]}
        ]}]}
        """).get()
        XCTAssertEqual(devices.map(\.name), ["Hub", "Keyboard"])
        XCTAssertEqual(devices.map(\.busPowerUsed), [nil, "100"])
    }

    func testUSBMalformedOrAbsentDatatypeNeverBecomesEmptyOrPartialSuccess() {
        for json in ["not json", "{}", "{\"SPUSBDataType\":{}}", "{\"SPUSBDataType\":[{}]}", """
        {"SPUSBDataType":[{"_name":"USB Bus","_items":[
          {"_name":"Valid","manufacturer":"Fixture"},
          {"vendor_id":"0x1234"}
        ]}]}
        """, """
        {"SPUSBDataType":[{"_name":"USB Bus","_items":[{"_name":"Unknown device"}]}]}
        """, """
        {"SPUSBDataType":[{"_name":"USB Bus","_items":"invalid"}]}
        """, """
        {"SPUSBDataType":[{"_name":"USB Bus","_items":[{"_name":"Device","vendor_id":12}]}]}
        """] {
            guard case .failure = DiagnosticService.parseUSBDevices(json) else { return XCTFail("Malformed or unsupported USB capture was accepted: \(json)") }
        }
    }

    func testSleepLogSupportedNoEventCaptureVersusUnsupportedOrMalformedCandidates() throws {
        let data = try DiagnosticService.parseSleepLog("""
        Time stamp                Domain                 Message
        2026-11-02 12:00:00 -0500 Assertions PID 42 Created UserIsActive
        2026-11-02 12:01:00 -0500 Wake Requests [process=fixture request=Maintenance]
        """).get()
        XCTAssertTrue(data.sessions.isEmpty)
        XCTAssertNil(data.lastWakeReason)
        for log in ["", "unrecognized log format", "Time stamp Domain Message", """
        2026-11-02 12:00:00 -0500 Assertions PID 42 Created UserIsActive
        malformed timestamp Sleep Entering Sleep state
        """, """
        2026-11-02 12:00:00 -0500 Sleep Entering Sleep state Charge:invalid
        """, """
        2026-11-02 12:00:00 -0500 Sleep Unsupported new event format
        """, """
        2026-11-02 12:00:00 -0500\tSleep\tUnsupported new event format
        """, """
        2026-11-02 12:00:00 -0500\tWake\tUnsupported new event format
        """, """
        2026-11-02 12:00:00 -0500 Wake Wake from Normal Sleep Charge:101%
        """] {
            guard case .failure = DiagnosticService.parseSleepLog(log) else { return XCTFail("Unrecognized or malformed sleep capture must be unavailable") }
        }
    }

    func testSleepLogPreservesMissingBatteryAndWakeReason() throws {
        let data = try DiagnosticService.parseSleepLog("""
        2026-11-02 12:00:00 -0500 Sleep Entering Sleep state due to 'Software Sleep'
        2026-11-02 13:30:00 -0500 Wake Wake from Normal Sleep
        """).get()
        let session = try XCTUnwrap(data.sessions.first)
        XCTAssertEqual(data.sessions.count, 1)
        XCTAssertEqual(session.duration, 90 * 60)
        XCTAssertNil(session.batteryAtSleep)
        XCTAssertNil(session.batteryAtWake)
        XCTAssertNil(session.batteryDelta)
        XCTAssertNil(session.wakeReason)
        XCTAssertNil(data.lastWakeReason)
        let tabData = try DiagnosticService.parseSleepLog("""
        2026-11-02 12:00:00 -0500\tSleep\tEntering Sleep state
        2026-11-02 13:30:00 -0500\tWake\tWake from Normal Sleep
        """).get()
        XCTAssertEqual(tabData.sessions.count, 1)
        XCTAssertEqual(tabData.sessions.first?.duration, 90 * 60)
    }

    func testSleepLogCapsFiveRecentSessionsAndSpecificUserActivityReason() throws {
        let log = (1...6).map { day in
            "2026-11-0\(day) 12:00:00 -0500 Sleep Entering Sleep state Charge:80%\n2026-11-0\(day) 13:00:00 -0500 Wake Wake from Normal Sleep due to UserActivity\tCharge:79%"
        }.joined(separator: "\n")
        let data = try DiagnosticService.parseSleepLog(log).get()
        XCTAssertEqual(data.sessions.count, 5)
        XCTAssertTrue(data.sessions[0].sleepTime > data.sessions[1].sleepTime)
        XCTAssertEqual(data.sessions.first?.batteryDelta, -1)
        XCTAssertEqual(data.lastWakeReason, "UserActivity")
        XCTAssertEqual(data.sessions.first?.humanWakeReason, "User Activity")
        XCTAssertEqual(SleepSession.humanReadableReason("User"), "Power Button")
    }

    func testObservedSettingsKeepMissingKeysAndRejectUnrecognizedOrMalformedData() throws {
        let settings = try DiagnosticService.parseObservedSettings("""
        System-wide power settings:
         hibernatemode 3
         standby\t1
        """).get()
        XCTAssertEqual(settings.map(\.key), SleepSetting.allCases.flatMap(\.pmsetKeys))
        XCTAssertEqual(settings.first?.actualValue, "3")
        XCTAssertEqual(settings.first?.id, "hibernatemode")
        XCTAssertNil(settings.first(where: { $0.key == "powernap" })?.actualValue)
        for output in ["", "unknownkey 1", "hibernatemode", "hibernatemode invalid", "hibernatemode 3\nhibernatemode 25"] {
            guard case .failure = DiagnosticService.parseObservedSettings(output) else { return XCTFail("Unsupported or malformed settings must be unavailable") }
        }
    }

    func testDiagnosticsPublishEachDatasetIndependently() async throws {
        let harness = FakeDependencies()
        harness.sleepResult = .failure(.unsupportedFormat)
        harness.usbResult = .success([USBDevice(name: "Fixture USB", busPowerUsed: nil)])
        harness.settingsResult = .success([ObservedSetting(key: "hibernatemode", actualValue: "3")])
        let viewModel = harness.makeViewModel()
        viewModel.loadDiagnostics()
        let work = harness.backgroundQueue
        harness.backgroundQueue = []
        await work[0]()
        harness.runMainQueue()
        guard case .failure = viewModel.sleepData else { return XCTFail("Sleep failure must remain visible") }
        XCTAssertTrue(viewModel.usbDevices.isLoading)
        XCTAssertTrue(viewModel.observedSettings.isLoading)
        await work[1]()
        harness.runMainQueue()
        guard case .success(let devices) = viewModel.usbDevices else { return XCTFail("Independent USB result should publish") }
        XCTAssertEqual(devices.first?.name, "Fixture USB")
        XCTAssertTrue(viewModel.isLoadingDiagnostics)
        await work[2]()
        harness.runMainQueue()
        guard case .success(let settings) = viewModel.observedSettings else { return XCTFail("Independent settings should publish") }
        XCTAssertEqual(settings.first?.actualValue, "3")
        guard case .failure = viewModel.sleepData else { return XCTFail("Other results must not erase the sleep failure") }
        XCTAssertFalse(viewModel.isLoadingDiagnostics)
    }

    func testNewRefreshClearsPriorDataAndRejectsObsoletePublicationIncludingLoading() async {
        let harness = FakeDependencies()
        harness.sleepResult = .success(SleepReadPayload(sessions: [], lastWakeReason: "Old reason"))
        harness.usbResult = .success([USBDevice(name: "Old USB", busPowerUsed: nil)])
        harness.settingsResult = .success([ObservedSetting(key: "hibernatemode", actualValue: "25")])
        let viewModel = harness.makeViewModel()
        viewModel.loadDiagnostics()
        await harness.runBackgroundQueue()
        let obsolete = harness.mainQueue
        harness.mainQueue = []
        viewModel.loadDiagnostics()
        obsolete.forEach { $0() }
        XCTAssertTrue(viewModel.sleepData.isLoading)
        XCTAssertTrue(viewModel.usbDevices.isLoading)
        XCTAssertTrue(viewModel.observedSettings.isLoading)
        harness.sleepResult = .failure(.malformedFormat)
        harness.usbResult = .success([])
        harness.settingsResult = .success([ObservedSetting(key: "hibernatemode", actualValue: "3")])
        await harness.runBackgroundQueue()
        harness.runMainQueue()
        obsolete.reversed().forEach { $0() }
        guard case .failure(.malformedFormat) = viewModel.sleepData else { return XCTFail("Old completion overwrote new failure") }
        guard case .success(let devices) = viewModel.usbDevices else { return XCTFail("Expected new USB result") }
        XCTAssertTrue(devices.isEmpty)
        guard case .success(let settings) = viewModel.observedSettings else { return XCTFail("Expected new settings") }
        XCTAssertEqual(settings.first?.actualValue, "3")
        XCTAssertFalse(viewModel.isLoadingDiagnostics)
        viewModel.loadDiagnostics()
        XCTAssertTrue(viewModel.sleepData.isLoading)
        XCTAssertTrue(viewModel.usbDevices.isLoading)
        XCTAssertTrue(viewModel.observedSettings.isLoading)
    }

    func testObservedValuesDoNotFollowPreferencesOrActiveState() async {
        let harness = FakeDependencies()
        harness.settingsResult = .success([ObservedSetting(key: "hibernatemode", actualValue: "3")])
        let viewModel = harness.makeViewModel()
        viewModel.loadDiagnostics()
        await harness.runBackgroundQueue()
        harness.runMainQueue()
        await viewModel.reconcile()
        viewModel.toggleSetting(.disableTcpKeepAlive)
        await viewModel.toggleMaster()
        guard case .success(let settings) = viewModel.observedSettings else { return XCTFail("Observation disappeared") }
        XCTAssertEqual(settings, [ObservedSetting(key: "hibernatemode", actualValue: "3")])
        XCTAssertEqual(harness.diagnosticCalls, 3)
        XCTAssertTrue(viewModel.isActive)
        XCTAssertEqual(harness.transport.values["hibernatemode"], 25)
    }

    private func completeOutcome(_ output: String) -> CommandOutcome {
        CommandOutcome(stdout: Data(output.utf8), stderr: Data(), termination: .exited(0), outputComplete: true, outputTruncated: false, directChildStopped: true)
    }

}

extension BenzoCoreTests {
    func testReleaseComparisonUsesNumericStableVersionsAndFixedRepositoryLinks() async throws {
        let bytes = try releaseFixture()
        var requests: [URLRequest] = []
        let checker = ReleaseChecker(load: { request in
            requests.append(request)
            return (bytes, releaseResponse())
        })
        let result = try await checker.check(installed: AppVersion(shortVersion: "0.9.0", buildVersion: "1"))
        XCTAssertEqual(result, .available(version: "0.10.0", page: URL(string: "https://github.com/chrisrogers37/benzo/releases/tag/v0.10.0")!))
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.url?.absoluteString, "https://api.github.com/repos/chrisrogers37/benzo/releases/latest")
        XCTAssertNil(requests.first?.value(forHTTPHeaderField: "Authorization"))
        let equal = try await checker.check(installed: AppVersion(shortVersion: "0.10.0", buildVersion: "9"))
        XCTAssertEqual(equal, .current(version: "0.10.0"))
        let newerLocal = try await checker.check(installed: AppVersion(shortVersion: "1.0.0", buildVersion: "10"))
        XCTAssertEqual(newerLocal, .ahead)
    }

    func testUnknownLocalVersionsNeverFetchOrClaimCurrent() async {
        var calls = 0
        let checker = ReleaseChecker(load: { _ in calls += 1; return (Data(), releaseResponse()) })
        for value in [nil, "", "0.3", "v0.3.0", "0.3.0-beta.1", "0.3.0+dev", "0.٣.0", "01.2.3", "999999999999999999999.0.0"] as [String?] {
            do {
                _ = try await checker.check(installed: AppVersion(shortVersion: value, buildVersion: "1"))
                XCTFail("Invalid local version must not compare: \(value ?? "nil")")
            } catch { XCTAssertEqual(error as? ReleaseCheckError, .unknownVersion) }
        }
        XCTAssertEqual(calls, 0)
    }

    func testInvalidReleaseMetadataCannotClaimCurrentOrOfferAnUpdate() async throws {
        let fixtures: [[String: Any]] = [
            ["draft": true], ["prerelease": true], ["published_at": NSNull()],
            ["published_at": "not-a-date"], ["tag_name": "v0.10.0-beta.1"],
            ["tag_name": "v0.10.0/../../evil"], ["assets": []],
            ["assets": [["name": "Benzo-0.10.0.dmg", "state": "uploaded", "size": 0]]],
            ["assets": [["name": "Benzo-0.10.0.dmg", "state": "starter", "size": 5]]],
        ]
        for fixture in fixtures {
            let data = try releaseFixture(fixture)
            let checker = ReleaseChecker(load: { _ in (data, releaseResponse()) })
            do {
                _ = try await checker.check(installed: AppVersion(shortVersion: "0.10.0", buildVersion: "1"))
                XCTFail("Unpublished/incomplete/invalid release must not be reported current")
            } catch { XCTAssertEqual(error as? ReleaseCheckError, .unavailable) }
        }
    }

    func testHTTPFailuresAndMalformedOrOversizedBodiesRemainUnavailable() async throws {
        for status in [301, 403, 404, 429, 500] {
            let checker = ReleaseChecker(load: { _ in (try releaseFixture(), releaseResponse(status: status)) })
            do {
                _ = try await checker.check(installed: AppVersion(shortVersion: "0.9.0", buildVersion: "1"))
                XCTFail("HTTP \(status) must not succeed")
            } catch { XCTAssertEqual(error as? ReleaseCheckError, .unavailable) }
        }
        for data in [Data("not json".utf8), Data(repeating: 32, count: 1_048_577)] {
            let checker = ReleaseChecker(load: { _ in (data, releaseResponse()) })
            do {
                _ = try await checker.check(installed: AppVersion(shortVersion: "0.9.0", buildVersion: "1"))
                XCTFail("Invalid/oversized body must not succeed")
            } catch { XCTAssertEqual(error as? ReleaseCheckError, .unavailable) }
        }
    }

    func testStreamingBodyStopsAtLimitInsteadOfDrainingTheResponse() async throws {
        var received = 0
        let stream = AsyncStream<UInt8>(unfolding: {
            received += 1
            return received <= 1_048_600 ? 32 : nil
        })
        do {
            _ = try await ReleaseChecker.collect(stream)
            XCTFail("Oversized response must stop during receipt")
        } catch { XCTAssertEqual(error as? ReleaseCheckError, .unavailable) }
        XCTAssertEqual(received, 1_048_577)
    }

    func testUnexpectedResponseURLIsRejectedEvenWithValidMetadata() async throws {
        let response = HTTPURLResponse(url: URL(string: "https://attacker.invalid/releases/latest")!,
                                       statusCode: 200, httpVersion: nil, headerFields: nil)!
        let checker = ReleaseChecker(load: { _ in (try releaseFixture(), response) })
        do {
            _ = try await checker.check(installed: AppVersion(shortVersion: "0.9.0", buildVersion: "1"))
            XCTFail("Valid-looking metadata from another URL must not offer an update")
        } catch { XCTAssertEqual(error as? ReleaseCheckError, .unavailable) }
    }
}

extension BenzoCoreTests {
    @MainActor
    func testUpdateChecksAreExplicitAndOnlyOpenTheBrowserAfterASeparateAction() async throws {
        var requests = 0
        var opened: [URL] = []
        let model = UpdateViewModel(version: AppVersion(shortVersion: "0.9.0", buildVersion: "1"),
                                    checker: ReleaseChecker(load: { _ in
            requests += 1
            return (try releaseFixture(), releaseResponse())
        }), openURL: { opened.append($0); return true })
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(model.state, .idle)
        await model.checkForUpdates()?.value
        XCTAssertEqual(requests, 1)
        XCTAssertTrue(opened.isEmpty)
        XCTAssertEqual(model.state, .checked(.available(version: "0.10.0", page: URL(string: "https://github.com/chrisrogers37/benzo/releases/tag/v0.10.0")!)))
        model.openReleasePage()
        XCTAssertEqual(opened.map(\.absoluteString), ["https://github.com/chrisrogers37/benzo/releases/tag/v0.10.0"])
    }

    @MainActor
    func testLeavingUpdatePanelDiscardsCompletedResultsWithoutCheckingAgain() async throws {
        for local in ["0.9.0", "0.10.0"] {
            var requests = 0
            let model = UpdateViewModel(version: AppVersion(shortVersion: local, buildVersion: "1"),
                                        checker: ReleaseChecker(load: { _ in
                requests += 1
                return (try releaseFixture(), releaseResponse())
            }), openURL: { _ in false })
            await model.checkForUpdates()?.value
            XCTAssertNotNil(model.message)
            model.openReleasePage()
            XCTAssertTrue(model.browserOpenFailed)
            model.cancelCheck()
            XCTAssertEqual(model.state, .idle)
            XCTAssertNil(model.message)
            XCTAssertNil(model.pageURL)
            XCTAssertFalse(model.browserOpenFailed)
            XCTAssertEqual(requests, 1)
        }
    }

    @MainActor
    func testCanceledCheckCannotReplaceNewerResultAndDuplicateClicksAreCoalesced() async throws {
        let started = expectation(description: "first request started")
        var first: CheckedContinuation<(Data, HTTPURLResponse), Error>?
        var calls = 0
        let model = UpdateViewModel(version: AppVersion(shortVersion: "0.10.0", buildVersion: "1"),
                                    checker: ReleaseChecker(load: { _ in
            calls += 1
            if calls == 1 {
                return try await withCheckedThrowingContinuation { first = $0; started.fulfill() }
            }
            throw URLError(.notConnectedToInternet)
        }), openURL: { _ in XCTFail("Checking must not open a browser"); return false })
        let abandoned = model.checkForUpdates()
        await fulfillment(of: [started], timeout: 1)
        XCTAssertNil(model.checkForUpdates())
        XCTAssertEqual(calls, 1)
        model.cancelCheck()
        await model.checkForUpdates()?.value
        XCTAssertEqual(model.state, .offline)
        first?.resume(returning: (try releaseFixture(), releaseResponse()))
        await abandoned?.value
        XCTAssertEqual(model.state, .offline)
        XCTAssertEqual(calls, 2)
    }

    @MainActor
    func testTransportCancellationClearsCheckingAndAllowsRetry() async {
        var calls = 0
        let model = UpdateViewModel(version: AppVersion(shortVersion: "0.3.0", buildVersion: "1"),
                                    checker: ReleaseChecker(load: { _ in
            calls += 1
            throw CancellationError()
        }), openURL: { _ in false })
        await model.checkForUpdates()?.value
        XCTAssertEqual(model.state, .idle)
        await model.checkForUpdates()?.value
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(model.state, .idle)
    }

    @MainActor
    func testUpdateErrorsNeverBecomeCurrentAndBrowserFailureIsVisible() async {
        for (error, expected) in [(URLError(.timedOut) as Error, UpdateViewModel.State.offline),
                                  (URLError(.notConnectedToInternet), .offline),
                                  (ReleaseCheckError.unavailable, .unavailable)] {
            let model = UpdateViewModel(version: AppVersion(shortVersion: "0.3.0", buildVersion: "1"),
                                        checker: ReleaseChecker(load: { _ in throw error }), openURL: { _ in false })
            await model.checkForUpdates()?.value
            XCTAssertEqual(model.state, expected)
            XCTAssertEqual(model.pageURL, URL(string: "https://github.com/chrisrogers37/benzo/releases"))
            model.openReleasePage()
            XCTAssertTrue(model.browserOpenFailed)
        }
    }
}
