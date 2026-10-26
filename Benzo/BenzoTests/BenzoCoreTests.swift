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

        XCTAssertFalse(store.hasBackup())
        try store.save(state)
        let backup = try store.load()

        XCTAssertTrue(store.hasBackup())
        XCTAssertEqual(backup.values, state.values)
        XCTAssertEqual(backup.capturedAt, clock.now)
    }

    func testBackupReadFailuresPropagateFromScratchStorage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("originals.json")
        let store = BackupService(fileURL: url, clock: FakeClock())

        XCTAssertThrowsError(try store.load())
        try Data("invalid JSON".utf8).write(to: url)
        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertTrue(error is DecodingError)
        }
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

    func testManualStartupSkipsSetupProbeMigrationAndQueuedWork() {
        let harness = FakeDependencies()
        harness.login.isEnabled = true
        let viewModel = harness.makeViewModel()

        XCTAssertTrue(viewModel.launchAtLogin)
        XCTAssertEqual(harness.setupChecks, 0)
        XCTAssertEqual(harness.migrationChecks, 0)
        XCTAssertEqual(harness.installCalls, 0)
        XCTAssertTrue(harness.commands.calls.isEmpty)
        XCTAssertEqual(harness.backup.accesses, 0)
        XCTAssertTrue(harness.preferences.writes.isEmpty)
        XCTAssertTrue(harness.mainQueue.isEmpty)
        XCTAssertTrue(harness.backgroundQueue.isEmpty)
        XCTAssertTrue(harness.clock.delayed.isEmpty)
        XCTAssertTrue(harness.clock.repeating.isEmpty)
        XCTAssertTrue(harness.login.calls.isEmpty)
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

    func testDelayedSleepUsesInjectedClockAndCommandRunner() {
        let harness = FakeDependencies()
        harness.preferences.values[BenzoPreferenceKey.isActive] = true
        harness.commands.error = ShellError.executionFailed("fake sleep denied")
        let viewModel = harness.makeViewModel()

        viewModel.sleepNow()
        XCTAssertTrue(harness.commands.calls.isEmpty)
        XCTAssertEqual(harness.clock.delayed.count, 1)
        harness.clock.fireDelayed()

        XCTAssertEqual(harness.commands.calls.map(\.arguments), [["sleepnow"]])
        XCTAssertEqual(viewModel.errorMessage, "fake sleep denied")
        XCTAssertFalse(viewModel.isSleeping)
    }

    func testScheduledSleepCanBeCancelledWithoutExecutingACommand() {
        let harness = FakeDependencies()
        let viewModel = harness.makeViewModel()

        viewModel.scheduleSleep(after: 60)
        XCTAssertEqual(harness.clock.repeating.count, 1)
        viewModel.cancelScheduledSleep()
        harness.clock.advance(by: 120)

        XCTAssertNil(viewModel.sleepTimerRemaining)
        XCTAssertTrue(harness.clock.repeating.allSatisfy { $0.token.isCancelled })
        XCTAssertTrue(harness.commands.calls.isEmpty)
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
