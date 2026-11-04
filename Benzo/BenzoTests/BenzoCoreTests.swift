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

    func testDiagnosticsAndTerminationUseInjectedCallbacks() {
        let harness = FakeDependencies()
        let viewModel = harness.makeViewModel()

        viewModel.loadDiagnostics()
        XCTAssertTrue(viewModel.isLoadingDiagnostics)
        XCTAssertEqual(harness.diagnosticCalls, 0)
        harness.runBackgroundQueue()
        XCTAssertEqual(harness.diagnosticCalls, 2)
        XCTAssertTrue(viewModel.isLoadingDiagnostics)
        harness.runMainQueue()
        XCTAssertEqual(harness.diagnosticCalls, 3)
        XCTAssertFalse(viewModel.isLoadingDiagnostics)
        viewModel.quit()
        XCTAssertEqual(harness.terminationCalls, 1)
        XCTAssertTrue(harness.commands.calls.isEmpty)
    }
}
