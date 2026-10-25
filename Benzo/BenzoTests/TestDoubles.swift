import Foundation

final class FakeCommandRunner: CommandRunning {
    struct Call {
        let executable: String
        let arguments: [String]
        let privileged: Bool
    }

    var calls: [Call] = []
    var error: Error?
    var output = "hibernatemode 3\nstandby 1"

    func runDirect(_ executable: String, _ arguments: [String]) throws -> String {
        calls.append(Call(executable: executable, arguments: arguments, privileged: false))
        if let error { throw error }
        return output
    }

    func runDirectWithSudo(_ executable: String, _ arguments: [String]) throws {
        calls.append(Call(executable: executable, arguments: arguments, privileged: true))
        if let error { throw error }
    }
}

final class FakeBackupStore: BackupStoring {
    var accesses = 0
    var backup = OriginalSettingsBackup(values: ["hibernatemode": "3"], capturedAt: Date(timeIntervalSince1970: 0))

    func hasBackup() -> Bool {
        accesses += 1
        return true
    }

    func save(_ state: PMSetState) throws {
        accesses += 1
        backup = OriginalSettingsBackup(values: state.values, capturedAt: Date(timeIntervalSince1970: 0))
    }

    func load() throws -> OriginalSettingsBackup {
        accesses += 1
        return backup
    }
}

final class FakePreferences: PreferenceStoring {
    var values: [String: Any] = [:]
    var writes: [String] = []

    func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
    func dictionary(forKey key: String) -> [String: Any]? { values[key] as? [String: Any] }
    func set(_ value: Any?, forKey key: String) {
        writes.append(key)
        values[key] = value
    }
}

final class FakeCancellation: BenzoCancellation {
    var isCancelled = false
    func cancel() { isCancelled = true }
}

final class FakeClock: BenzoClock {
    struct Repeating {
        let token: FakeCancellation
        let action: (any BenzoCancellation) -> Void
    }

    var now = Date(timeIntervalSince1970: 1_700_000_000)
    var delayed: [() -> Void] = []
    var repeating: [Repeating] = []

    func schedule(after delay: TimeInterval, perform: @escaping () -> Void) {
        delayed.append(perform)
    }

    func scheduleRepeating(every interval: TimeInterval, perform: @escaping (any BenzoCancellation) -> Void) -> any BenzoCancellation {
        let token = FakeCancellation()
        repeating.append(Repeating(token: token, action: perform))
        return token
    }

    func fireDelayed() {
        let pending = delayed
        delayed = []
        pending.forEach { $0() }
    }

    func advance(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
        for item in repeating where !item.token.isCancelled {
            item.action(item.token)
        }
    }
}

final class FakeLoginItem: LoginItemClient {
    var isEnabled = false
    var calls: [String] = []
    var error: Error?

    func register() throws {
        calls.append("register")
        if let error { throw error }
    }

    func unregister() throws {
        calls.append("unregister")
        if let error { throw error }
    }
}

/// In-memory boundaries only. No live factory, app host, standard preferences, real
/// timers/queues, process execution, ServiceManagement, or application termination.
final class FakeDependencies {
    let commands = FakeCommandRunner()
    let backup = FakeBackupStore()
    let preferences = FakePreferences()
    let clock = FakeClock()
    let login = FakeLoginItem()
    var setupChecks = 0
    var migrationChecks = 0
    var installCalls = 0
    var diagnosticCalls = 0
    var terminationCalls = 0
    var mainQueue: [() -> Void] = []
    var backgroundQueue: [() -> Void] = []

    func makeViewModel() -> BenzoViewModel {
        let dependencies = BenzoDependencies(
            commands: commands,
            backup: backup,
            preferences: preferences,
            clock: clock,
            loginItem: login,
            isSetupComplete: { self.setupChecks += 1; return false },
            needsSudoersUpdate: { self.migrationChecks += 1; return true },
            installSudoersRule: { self.installCalls += 1 },
            fetchSleepData: { self.diagnosticCalls += 1; return ([], nil) },
            fetchUSBDevices: { self.diagnosticCalls += 1; return [] },
            fetchSleepBlockers: { self.diagnosticCalls += 1; return [] },
            verifySettings: { _, _ in self.diagnosticCalls += 1; return [] },
            runInBackground: { self.backgroundQueue.append($0) },
            runOnMain: { self.mainQueue.append($0) },
            terminate: { self.terminationCalls += 1 }
        )
        return BenzoViewModel(dependencies: dependencies, startupPolicy: .manual)
    }

    func runBackgroundQueue() {
        let pending = backgroundQueue
        backgroundQueue = []
        pending.forEach { $0() }
    }

    func runMainQueue() {
        let pending = mainQueue
        mainQueue = []
        pending.forEach { $0() }
    }
}
