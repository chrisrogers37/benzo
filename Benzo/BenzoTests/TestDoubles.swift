import Foundation

final class FakePreferences: PreferenceStoring {
    var values: [String: Any] = [:]
    var writes: [String] = []
    func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
    func dictionary(forKey key: String) -> [String: Any]? { values[key] as? [String: Any] }
    func set(_ value: Any?, forKey key: String) { writes.append(key); values[key] = value }
}

final class FakeClock: BenzoClock {
    var now = Date(timeIntervalSince1970: 1_700_000_000)
}

final class FakeLoginItem: LoginItemClient {
    var isEnabled = false
    var calls: [String] = []
    var error: Error?
    func register() throws { calls.append("register"); if let error { throw error } }
    func unregister() throws { calls.append("unregister"); if let error { throw error } }
}

final class IntegrationRecoveryStore: RecoveryStoring {
    var journal: RecoveryJournal?
    var fence: ExecutionFence?
    var receipt: RecoveryJournal?
    var legacy: Data?
    var error: Error?
    var lockCalls = 0
    var journalCommits = 0
    func acquireLock() throws { lockCalls += 1; if let error { throw error } }
    func loadJournal() throws -> RecoveryJournal? { if let error { throw error }; return journal }
    func commitJournal(_ journal: RecoveryJournal) throws {
        if let error { throw error }
        self.journal = journal
        journalCommits += 1
    }
    func saveResolvedReceipt(_ journal: RecoveryJournal) throws { if let error { throw error }; receipt = journal }
    func loadFence() throws -> ExecutionFence? { if let error { throw error }; return fence }
    func commitFence(_ fence: ExecutionFence) throws { if let error { throw error }; self.fence = fence }
    func loadLegacyEvidence() throws -> Data? { if let error { throw error }; return legacy }
}

final class IntegrationRecoveryTransport: RecoveryCommanding {
    struct Write: Equatable { let cell: ManagedCell; let value: Int }
    var writes: [Write] = []
    var captureCalls = 0
    var captureError: Error?
    var writeOutcome: RecoveryWriteOutcome = .completed(status: 0)
    var values: [String: Int] = ["hibernatemode": 3, "standby": 1, "autopoweroff": 1,
                                "powernap": 1, "tcpkeepalive": 1, "proximitywake": 1, "womp": 1]
    func capture() async throws -> ProfileSnapshot {
        captureCalls += 1
        if let captureError { throw captureError }
        let raw = "AC Power:\n" + values.keys.sorted().map { " \($0) \(values[$0]!)" }.joined(separator: "\n")
        return try ProfileSnapshot(parsing: raw)
    }
    func write(cell: ManagedCell, value: Int, operationID: UUID) async -> RecoveryWriteOutcome {
        writes.append(Write(cell: cell, value: value))
        if case .completed(status: 0) = writeOutcome { values[cell.key.rawValue] = value }
        return writeOutcome
    }
}

/// In-memory boundaries only. Never selects a live adapter, standard preferences,
/// process execution, ServiceManagement, or actual application termination.
@MainActor
final class FakeDependencies {
    let store = IntegrationRecoveryStore()
    let transport = IntegrationRecoveryTransport()
    let preferences = FakePreferences()
    let login = FakeLoginItem()
    var permissionObservation: PermissionObservation = .noLegacyRule
    var permissionObservations = 0
    var diagnosticCalls = 0
    var terminationCalls = 0
    var mainQueue: [@MainActor () -> Void] = []
    var backgroundQueue: [() async -> Void] = []
    var sleepResult: Result<SleepReadPayload, DiagnosticReadError> = .success(SleepReadPayload(sessions: [], lastWakeReason: nil))
    var usbResult: Result<[USBDevice], DiagnosticReadError> = .success([])
    var settingsResult: Result<[ObservedSetting], DiagnosticReadError> = .success([])
    private(set) var coordinator: OperationCoordinator!

    func makeViewModel(startupPolicy: BenzoStartupPolicy = .manual) -> BenzoViewModel {
        coordinator = OperationCoordinator(
            store: store, transport: transport, uid: 501,
            hostID: "99999999-9999-4999-8999-999999999999",
            bootID: { "11111111-1111-4111-8111-111111111111" },
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            legacyActive: { self.preferences.bool(forKey: BenzoPreferenceKey.isActive) },
            legacyRule: { self.permissionObservation }
        )
        let dependencies = BenzoDependencies(
            coordinator: coordinator,
            preferences: preferences,
            loginItem: login,
            observePermission: { self.permissionObservations += 1; return self.permissionObservation },
            fetchSleepData: { self.diagnosticCalls += 1; return self.sleepResult },
            fetchUSBDevices: { self.diagnosticCalls += 1; return self.usbResult },
            readObservedSettings: { self.diagnosticCalls += 1; return self.settingsResult },
            runInBackground: { self.backgroundQueue.append($0) },
            runOnMain: { self.mainQueue.append($0) },
            terminate: { self.terminationCalls += 1 }
        )
        return BenzoViewModel(dependencies: dependencies, startupPolicy: startupPolicy)
    }

    func runBackgroundQueue() async {
        let pending = backgroundQueue
        backgroundQueue = []
        for work in pending { await work() }
    }
    func runMainQueue() {
        let pending = mainQueue
        mainQueue = []
        pending.forEach { $0() }
    }
}

final class FakeReadCommandRunner: ReadCommandRunning {
    var calls: [ReadCommand] = []
    var outcome = CommandOutcome(stdout: Data(), stderr: Data(), termination: .exited(0), outputComplete: true, outputTruncated: false, directChildStopped: true)
    func run(_ command: ReadCommand) async -> CommandOutcome { calls.append(command); return outcome }
}
