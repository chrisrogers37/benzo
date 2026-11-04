import Foundation
import XCTest

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

    func testDanglingParentSymlinkIsUnknownAndKeepsSelectionFrozen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let link = directory.appendingPathComponent("recovery")
        let missingTarget = directory.appendingPathComponent("missing-directory").path
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: missingTarget)

        for relativePath in ["originals.json", "nested/originals.json"] {
            let store = BackupService(fileURL: link.appendingPathComponent(relativePath), clock: FakeClock())
            guard case .unknown = store.evidencePresence() else {
                return XCTFail("A dangling parent symlink must not count as confirmed absence")
            }
            let harness = FakeDependencies()
            let viewModel = harness.makeViewModel(backupStore: store)
            let originalStates = viewModel.settingStates

            XCTAssertTrue(viewModel.isSelectionEditBlocked)
            viewModel.toggleSetting(.hibernateMode)

            XCTAssertEqual(viewModel.settingStates, originalStates)
            XCTAssertEqual(viewModel.errorMessage, BenzoViewModel.selectionEditBlockedReason)
            XCTAssertTrue(harness.preferences.writes.isEmpty)
            XCTAssertTrue(harness.commands.calls.isEmpty)
            XCTAssertTrue(harness.mainQueue.isEmpty)
            XCTAssertTrue(harness.backgroundQueue.isEmpty)
            XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), missingTarget)
            XCTAssertFalse(FileManager.default.fileExists(atPath: missingTarget))
        }
    }

    func testUnreadableBackupPathIsUnknownAndBlocksSelection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        let url = directory.appendingPathComponent("originals.json")
        let bytes = Data("retain unreadable evidence".utf8)
        try bytes.write(to: url)
        let store = BackupService(fileURL: url, clock: FakeClock())
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: directory.path)

        if store.evidencePresence() == .present {
            throw XCTSkip("This test account can bypass scratch-directory permissions")
        }
        guard case .unknown = store.evidencePresence() else {
            return XCTFail("An unreadable path must not count as confirmed absence")
        }
        let harness = FakeDependencies()
        let viewModel = harness.makeViewModel(backupStore: store)
        let originalStates = viewModel.settingStates
        viewModel.toggleSetting(.hibernateMode)

        XCTAssertEqual(viewModel.settingStates, originalStates)
        XCTAssertEqual(viewModel.errorMessage, BenzoViewModel.selectionEditBlockedReason)
        XCTAssertTrue(harness.preferences.writes.isEmpty)
        XCTAssertTrue(harness.commands.calls.isEmpty)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testCommandErrorsPropagateThroughPMSetService() {
        let runner = FakeCommandRunner()
        let service = PMSetService(runner: runner)
        runner.error = ShellError.executionFailed("fake command failure")

        XCTAssertThrowsError(try service.readCurrentState()) { error in
            XCTAssertEqual(error.localizedDescription, "fake command failure")
        }
        XCTAssertThrowsError(try service.applySettings([.hibernateMode])) { error in
            XCTAssertEqual(error.localizedDescription, "fake command failure")
        }
        XCTAssertEqual(runner.calls.map(\.privileged), [false, true])
    }

    func testCommandErrorIsVisibleThroughViewModel() {
        let harness = FakeDependencies()
        harness.commands.error = ShellError.executionFailed("fake write denied")
        let viewModel = harness.makeViewModel()

        viewModel.toggleMaster()

        XCTAssertEqual(viewModel.errorMessage, "fake write denied")
        XCTAssertFalse(viewModel.isActive)
        XCTAssertEqual(harness.commands.calls.count, 1)
        XCTAssertTrue(harness.commands.calls[0].privileged)
    }

    func testManualStartupSkipsPermissionObservationAndQueuedWork() {
        let harness = FakeDependencies()
        harness.login.isEnabled = true
        let viewModel = harness.makeViewModel()

        XCTAssertTrue(viewModel.launchAtLogin)
        XCTAssertEqual(viewModel.permissionObservation, .unknown("Not checked"))
        XCTAssertTrue(viewModel.showPermissionStatus)
        XCTAssertEqual(harness.permissionObservations, 0)
        XCTAssertTrue(harness.commands.calls.isEmpty)
        XCTAssertEqual(harness.backup.accesses, 0)
        XCTAssertEqual(harness.backup.evidenceChecks, 0)
        XCTAssertTrue(harness.preferences.writes.isEmpty)
        XCTAssertTrue(harness.mainQueue.isEmpty)
        XCTAssertTrue(harness.backgroundQueue.isEmpty)
        XCTAssertTrue(harness.login.calls.isEmpty)
    }

    func testAutomaticStartupOnlyObservesPermissionWithoutChangingSavedState() {
        for observation in [PermissionObservation.noLegacyRule, .legacyRulePresent, .unknown("unreadable")] {
            let harness = FakeDependencies()
            harness.permissionObservation = observation
            harness.preferences.values[BenzoPreferenceKey.sudoersRuleVersion] = 0
            harness.preferences.values[BenzoPreferenceKey.isActive] = true
            let viewModel = harness.makeViewModel(startupPolicy: .automatic)

            XCTAssertEqual(viewModel.permissionObservation, observation)
            XCTAssertTrue(viewModel.showPermissionStatus)
            XCTAssertTrue(viewModel.isActive)
            XCTAssertEqual(harness.permissionObservations, 1)
            XCTAssertEqual(harness.preferences.values[BenzoPreferenceKey.sudoersRuleVersion] as? Int, 0)
            XCTAssertTrue(harness.commands.calls.isEmpty)
            XCTAssertEqual(harness.backup.accesses, 0)
            XCTAssertEqual(harness.backup.evidenceChecks, 0)
            XCTAssertTrue(harness.preferences.writes.isEmpty)
            XCTAssertTrue(harness.mainQueue.isEmpty)
            XCTAssertTrue(harness.backgroundQueue.isEmpty)
            XCTAssertTrue(harness.login.calls.isEmpty)
        }
    }

    func testPermissionRefreshAndBackOnlyUpdateObservationAndNavigation() {
        for active in [false, true] {
            let harness = FakeDependencies()
            harness.preferences.values[BenzoPreferenceKey.isActive] = active
            harness.preferences.values[BenzoPreferenceKey.sudoersRuleVersion] = 2
            let viewModel = harness.makeViewModel()
            let states = viewModel.settingStates
            viewModel.errorMessage = "Preserve unrelated error"
            var stateChanges = 0
            viewModel.onStateChange = { _ in stateChanges += 1 }

            for observation in [PermissionObservation.noLegacyRule, .legacyRulePresent, .unknown("unreadable")] {
                harness.permissionObservation = observation
                viewModel.refreshPermissionObservation()
                XCTAssertEqual(viewModel.permissionObservation, observation)
                XCTAssertTrue(viewModel.showPermissionStatus)
            }
            viewModel.showPermissionStatus = false

            XCTAssertFalse(viewModel.showPermissionStatus)
            XCTAssertEqual(viewModel.permissionObservation, .unknown("unreadable"))
            XCTAssertEqual(harness.permissionObservations, 3)
            XCTAssertEqual(viewModel.isActive, active)
            XCTAssertEqual(viewModel.settingStates, states)
            XCTAssertEqual(viewModel.errorMessage, "Preserve unrelated error")
            XCTAssertEqual(stateChanges, 0)
            XCTAssertEqual(harness.preferences.values[BenzoPreferenceKey.sudoersRuleVersion] as? Int, 2)
            XCTAssertTrue(harness.preferences.writes.isEmpty)
            XCTAssertTrue(harness.commands.calls.isEmpty)
            XCTAssertEqual(harness.backup.accesses, 0)
            XCTAssertEqual(harness.backup.evidenceChecks, 0)
            XCTAssertTrue(harness.mainQueue.isEmpty)
            XCTAssertTrue(harness.backgroundQueue.isEmpty)
            XCTAssertTrue(harness.login.calls.isEmpty)
        }
    }

    func testSleepNowRefusesWithoutCommandsBackupsPreferencesOrContinuations() {
        for isActive in [false, true] {
            for evidence in [BackupEvidencePresence.absent, .present, .unknown("unreadable")] {
                let harness = FakeDependencies()
                harness.preferences.values[BenzoPreferenceKey.isActive] = isActive
                harness.backup.evidence = evidence
                let viewModel = harness.makeViewModel()
                let originalStates = viewModel.settingStates
                var stateChanges = 0
                viewModel.onStateChange = { _ in stateChanges += 1 }

                viewModel.sleepNow()
                viewModel.sleepNow()

                XCTAssertEqual(viewModel.errorMessage, BenzoViewModel.sleepUnavailableReason)
                XCTAssertEqual(viewModel.isActive, isActive)
                XCTAssertEqual(viewModel.settingStates, originalStates)
                XCTAssertEqual(stateChanges, 0)
                XCTAssertTrue(harness.commands.calls.isEmpty)
                XCTAssertEqual(harness.backup.accesses, 0)
                XCTAssertEqual(harness.backup.evidenceChecks, 0)
                XCTAssertTrue(harness.preferences.writes.isEmpty)
                XCTAssertTrue(harness.mainQueue.isEmpty)
                XCTAssertTrue(harness.backgroundQueue.isEmpty)
                XCTAssertTrue(harness.login.calls.isEmpty)
            }
        }
    }

    func testActiveSelectionIsRejectedBeforePreferencePersistence() {
        let harness = FakeDependencies()
        harness.preferences.values[BenzoPreferenceKey.isActive] = true
        harness.backup.evidence = .absent
        let viewModel = harness.makeViewModel()
        let originalStates = viewModel.settingStates

        viewModel.toggleSetting(.hibernateMode)

        XCTAssertEqual(viewModel.settingStates, originalStates)
        XCTAssertEqual(viewModel.errorMessage, BenzoViewModel.selectionEditBlockedReason)
        XCTAssertTrue(harness.preferences.writes.isEmpty)
        XCTAssertTrue(harness.commands.calls.isEmpty)
        XCTAssertEqual(harness.backup.accesses, 0)
        XCTAssertTrue(harness.mainQueue.isEmpty)
        XCTAssertTrue(harness.backgroundQueue.isEmpty)
    }

    func testPresentAndUnknownEvidenceRejectInactiveSelectionBeforePersistence() {
        for evidence in [BackupEvidencePresence.present, .unknown("metadata unavailable")] {
            let harness = FakeDependencies()
            harness.backup.evidence = evidence
            let viewModel = harness.makeViewModel()
            let originalStates = viewModel.settingStates

            XCTAssertTrue(viewModel.isSelectionEditBlocked)
            viewModel.toggleSetting(.hibernateMode)

            XCTAssertEqual(viewModel.settingStates, originalStates)
            XCTAssertEqual(viewModel.errorMessage, BenzoViewModel.selectionEditBlockedReason)
            XCTAssertTrue(harness.preferences.writes.isEmpty)
            XCTAssertTrue(harness.commands.calls.isEmpty)
            XCTAssertEqual(harness.backup.accesses, 0)
            XCTAssertTrue(harness.mainQueue.isEmpty)
            XCTAssertTrue(harness.backgroundQueue.isEmpty)
        }
    }

    func testConfirmedAbsentEvidenceAllowsInactivePreferenceEditOnly() {
        let harness = FakeDependencies()
        harness.backup.evidence = .absent
        let viewModel = harness.makeViewModel()
        let originalValue = viewModel.settingStates[.hibernateMode]!

        XCTAssertFalse(viewModel.isSelectionEditBlocked)
        viewModel.toggleSetting(.hibernateMode)

        XCTAssertEqual(viewModel.settingStates[.hibernateMode], !originalValue)
        let saved = harness.preferences.values[BenzoPreferenceKey.settingStates] as? [String: Bool]
        XCTAssertEqual(saved?[SleepSetting.hibernateMode.rawValue], !originalValue)
        XCTAssertEqual(harness.preferences.writes, [BenzoPreferenceKey.settingStates])
        XCTAssertFalse(viewModel.isActive)
        XCTAssertTrue(harness.commands.calls.isEmpty)
        XCTAssertEqual(harness.backup.accesses, 0)
        XCTAssertTrue(harness.mainQueue.isEmpty)
        XCTAssertTrue(harness.backgroundQueue.isEmpty)
    }

    func testSelectionGuardRechecksEvidenceImmediatelyBeforeEdit() {
        let harness = FakeDependencies()
        harness.backup.evidence = .absent
        let viewModel = harness.makeViewModel()
        let originalStates = viewModel.settingStates
        XCTAssertFalse(viewModel.isSelectionEditBlocked)
        harness.backup.evidence = .present

        viewModel.toggleSetting(.hibernateMode)

        XCTAssertEqual(viewModel.settingStates, originalStates)
        XCTAssertEqual(harness.backup.evidenceChecks, 2)
        XCTAssertTrue(harness.preferences.writes.isEmpty)
        XCTAssertTrue(harness.commands.calls.isEmpty)
    }

    func testValidAndCorruptScratchEvidenceKeepInactiveSelectionFrozen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("originals.json")
        let store = BackupService(fileURL: url, clock: FakeClock())
        try store.save(PMSetState(parsing: "hibernatemode 3"))
        let validBytes = try Data(contentsOf: url)

        for bytes in [validBytes, Data("invalid JSON".utf8)] {
            try bytes.write(to: url)
            let harness = FakeDependencies()
            let viewModel = harness.makeViewModel(backupStore: store)
            let originalStates = viewModel.settingStates

            XCTAssertTrue(viewModel.isSelectionEditBlocked)
            viewModel.toggleSetting(.hibernateMode)

            XCTAssertEqual(viewModel.settingStates, originalStates)
            XCTAssertEqual(viewModel.errorMessage, BenzoViewModel.selectionEditBlockedReason)
            XCTAssertTrue(harness.preferences.writes.isEmpty)
            XCTAssertTrue(harness.commands.calls.isEmpty)
            XCTAssertEqual(try Data(contentsOf: url), bytes)
        }
    }

    func testLegacyOffAndRestoreRetainEvidenceAndKeepSelectionFrozen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("originals.json")
        let store = BackupService(fileURL: url, clock: FakeClock())
        try store.save(PMSetState(parsing: "hibernatemode 3"))
        let originalBytes = try Data(contentsOf: url)

        for useRestore in [false, true] {
            let harness = FakeDependencies()
            harness.preferences.values[BenzoPreferenceKey.isActive] = true
            let viewModel = harness.makeViewModel(backupStore: store)
            let originalStates = viewModel.settingStates
            if useRestore {
                viewModel.revertToDefaults()
            } else {
                viewModel.toggleMaster()
            }
            XCTAssertFalse(viewModel.isActive)
            XCTAssertEqual(harness.commands.calls.map(\.arguments), [["-a", "hibernatemode", "3"]])
            XCTAssertEqual(store.evidencePresence(), .present)
            let writesAfterRestore = harness.preferences.writes

            viewModel.toggleSetting(.hibernateMode)

            XCTAssertEqual(viewModel.settingStates, originalStates)
            XCTAssertEqual(viewModel.errorMessage, BenzoViewModel.selectionEditBlockedReason)
            XCTAssertEqual(harness.preferences.writes, writesAfterRestore)
            XCTAssertEqual(harness.commands.calls.count, 1)
            XCTAssertEqual(try Data(contentsOf: url), originalBytes)
        }
    }

    func testLoginSetterReachesOnlyInjectedRegisterAndUnregister() {
        let harness = FakeDependencies()
        let viewModel = harness.makeViewModel()

        viewModel.launchAtLogin = true
        viewModel.launchAtLogin = false

        XCTAssertEqual(harness.login.calls, ["register", "unregister"])
        XCTAssertTrue(harness.commands.calls.isEmpty)
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
        XCTAssertTrue(harness.commands.calls.isEmpty)
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
        harness.backup.evidence = .absent
        harness.settingsResult = .success([ObservedSetting(key: "hibernatemode", actualValue: "3")])
        let viewModel = harness.makeViewModel()
        viewModel.loadDiagnostics()
        await harness.runBackgroundQueue()
        harness.runMainQueue()
        viewModel.toggleSetting(.hibernateMode)
        viewModel.isActive = true
        guard case .success(let settings) = viewModel.observedSettings else { return XCTFail("Observation disappeared") }
        XCTAssertEqual(settings, [ObservedSetting(key: "hibernatemode", actualValue: "3")])
        XCTAssertEqual(harness.diagnosticCalls, 3)
        XCTAssertTrue(harness.commands.calls.isEmpty)
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
