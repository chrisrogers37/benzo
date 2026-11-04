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
        XCTAssertEqual(harness.permissionObservations, 1)
        XCTAssertTrue(harness.transport.writes.isEmpty)
        XCTAssertTrue(harness.preferences.writes.isEmpty)
        XCTAssertTrue(harness.login.calls.isEmpty)
    }

    func testPermissionRefreshOnlyUpdatesObservationAndNavigation() {
        let harness = FakeDependencies()
        let viewModel = harness.makeViewModel()
        let states = viewModel.settingStates
        viewModel.errorMessage = "Preserve unrelated error"
        var stateChanges = 0
        viewModel.onStateChange = { _ in stateChanges += 1 }
        for observation in [PermissionObservation.noLegacyRule, .legacyRulePresent, .unknown("unreadable")] {
            harness.permissionObservation = observation
            viewModel.refreshPermissionObservation()
            XCTAssertEqual(viewModel.permissionObservation, observation)
        }
        viewModel.showPermissionStatus = false
        XCTAssertEqual(viewModel.settingStates, states)
        XCTAssertEqual(viewModel.errorMessage, "Preserve unrelated error")
        XCTAssertEqual(stateChanges, 0)
        XCTAssertEqual(harness.permissionObservations, 3)
        XCTAssertTrue(harness.preferences.writes.isEmpty)
        XCTAssertTrue(harness.transport.writes.isEmpty)
        XCTAssertEqual(harness.store.lockCalls, 0)
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
