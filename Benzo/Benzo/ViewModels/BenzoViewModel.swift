import Combine
import Foundation

final class BenzoViewModel: ObservableObject {
    @Published var isActive: Bool {
        didSet { dependencies.preferences.set(isActive, forKey: BenzoPreferenceKey.isActive) }
    }
    @Published var settingStates: [SleepSetting: Bool] {
        didSet { persistSettingStates() }
    }
    @Published var launchAtLogin: Bool = false {
        didSet {
            guard isInitialized else { return }
            updateLaunchAtLogin()
        }
    }
    @Published var needsSetup: Bool = false
    @Published var errorMessage: String?
    @Published var isSleeping = false

    // Diagnostics
    @Published var showDiagnostics = false
    @Published var isLoadingDiagnostics = false
    @Published var sleepSessions: [SleepSession] = []
    @Published var lastWakeReason: String?
    @Published var usbDevices: [USBDevice] = []
    @Published var settingsVerification: [SettingVerification] = []
    @Published var sleepBlockers: [SleepBlocker] = []
    @Published var sleepTimerRemaining: TimeInterval?

    var onStateChange: ((Bool) -> Void)?
    private var isInitialized = false
    private var sleepTimer: (any BenzoCancellation)?
    private let dependencies: BenzoDependencies
    private let pmset: PMSetService

    init(dependencies: BenzoDependencies, startupPolicy: BenzoStartupPolicy) {
        self.dependencies = dependencies
        self.pmset = PMSetService(runner: dependencies.commands)
        let savedActive = dependencies.preferences.bool(forKey: BenzoPreferenceKey.isActive)

        if let data = dependencies.preferences.dictionary(forKey: BenzoPreferenceKey.settingStates) as? [String: Bool] {
            var states: [SleepSetting: Bool] = [:]
            for setting in SleepSetting.allCases {
                states[setting] = data[setting.rawValue] ?? setting.defaultEnabled
            }
            self.settingStates = states
        } else {
            var states: [SleepSetting: Bool] = [:]
            for setting in SleepSetting.allCases {
                states[setting] = setting.defaultEnabled
            }
            self.settingStates = states
        }

        self.isActive = savedActive

        self.launchAtLogin = dependencies.loginItem.isEnabled
        self.isInitialized = true

        if startupPolicy == .automatic {
            self.needsSetup = !dependencies.isSetupComplete()
            if dependencies.needsSudoersUpdate() {
                dependencies.runOnMain {
                    try? dependencies.installSudoersRule()
                }
            }
        }
    }

    func runSetup() {
        do {
            try dependencies.installSudoersRule()
            needsSetup = false
            errorMessage = nil
        } catch ShellError.userCancelled {
            // Stay on setup screen
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var activeCount: Int {
        settingStates.values.filter { $0 }.count
    }

    func toggleMaster() {
        if isActive {
            deactivate()
        } else {
            activate()
        }
    }

    func toggleSetting(_ setting: SleepSetting) {
        settingStates[setting]?.toggle()
        if isActive {
            applyCurrentSettings()
        }
    }

    func revertToDefaults() {
        guard let backup = try? dependencies.backup.load() else {
            errorMessage = "Nothing to revert — activate Benzo first."
            return
        }
        do {
            try pmset.restoreValues(backup)
            isActive = false
            onStateChange?(false)
            errorMessage = nil
        } catch ShellError.userCancelled {
            // Don't change state
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func quit() {
        if isActive, let backup = try? dependencies.backup.load() {
            try? pmset.restoreValues(backup)
        }
        dependencies.terminate()
    }

    func sleepNow() {
        isSleeping = true
        errorMessage = nil

        do {
            // If Deep Sleep isn't active, enable it first
            if !isActive {
                if !dependencies.backup.hasBackup() {
                    let state = try pmset.readCurrentState()
                    try dependencies.backup.save(state)
                }
                let enabled = SleepSetting.allCases.filter { settingStates[$0] == true }
                try pmset.applySettings(enabled)
                isActive = true
                onStateChange?(true)
            }

            // Brief delay to let settings propagate, then sleep
            let pmset = self.pmset
            dependencies.clock.schedule(after: 0.5) { [weak self] in
                do {
                    try pmset.sleepNow()
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
                self?.isSleeping = false
            }
        } catch ShellError.userCancelled {
            isSleeping = false
        } catch {
            errorMessage = error.localizedDescription
            isSleeping = false
        }
    }

    // MARK: - Timed Sleep

    func scheduleSleep(after seconds: TimeInterval) {
        cancelScheduledSleep()
        let fireDate = dependencies.clock.now.addingTimeInterval(seconds)
        sleepTimerRemaining = seconds

        sleepTimer = dependencies.clock.scheduleRepeating(every: 1) { [weak self] timer in
            guard let self else { timer.cancel(); return }
            let remaining = fireDate.timeIntervalSince(self.dependencies.clock.now)
            if remaining <= 0 {
                timer.cancel()
                self.sleepTimer = nil
                self.sleepTimerRemaining = nil
                self.executeSleepWithBlockerKill()
            } else {
                self.sleepTimerRemaining = remaining
            }
        }
    }

    func cancelScheduledSleep() {
        sleepTimer?.cancel()
        sleepTimer = nil
        sleepTimerRemaining = nil
    }

    private func executeSleepWithBlockerKill() {
        pmset.killCaffeinateProcesses()
        sleepNow()
    }

    // MARK: - Drift Detection

    func verifyAndCorrectSettings() {
        guard isActive else {
            if !sleepBlockers.isEmpty {
                sleepBlockers = []
            }
            return
        }

        let enabled = SleepSetting.allCases.filter { settingStates[$0] == true }
        guard !enabled.isEmpty else { return }

        let dependencies = self.dependencies
        let pmset = self.pmset
        dependencies.runInBackground { [weak self] in
            guard let currentState = try? pmset.readCurrentState() else { return }

            var drifted = false
            for setting in enabled {
                for (key, value) in setting.pmsetCommands {
                    if currentState.values[key] != value {
                        drifted = true
                        break
                    }
                }
                if drifted { break }
            }

            let blockers = dependencies.fetchSleepBlockers()

            dependencies.runOnMain {
                if drifted {
                    self?.applyCurrentSettings()
                }
                self?.sleepBlockers = blockers
            }
        }
    }

    // MARK: - Diagnostics

    func loadDiagnostics() {
        isLoadingDiagnostics = true
        let dependencies = self.dependencies
        dependencies.runInBackground { [weak self] in
            let (sessions, wakeReason) = dependencies.fetchSleepData()
            let usb = dependencies.fetchUSBDevices()

            dependencies.runOnMain {
                guard let self else { return }
                self.sleepSessions = sessions
                self.lastWakeReason = wakeReason.map { SleepSession.humanReadableReason($0) }
                self.usbDevices = usb
                self.settingsVerification = dependencies.verifySettings(self.settingStates, self.isActive)
                self.isLoadingDiagnostics = false
            }
        }
    }

    // MARK: - Private

    private func activate() {
        do {
            // Backup current values on first activation
            if !dependencies.backup.hasBackup() {
                let state = try pmset.readCurrentState()
                try dependencies.backup.save(state)
            }

            let enabled = SleepSetting.allCases.filter { settingStates[$0] == true }
            try pmset.applySettings(enabled)
            isActive = true
            onStateChange?(true)
            errorMessage = nil
        } catch ShellError.userCancelled {
            // Don't change state
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deactivate() {
        guard let backup = try? dependencies.backup.load() else {
            // No backup — just toggle off visually
            isActive = false
            onStateChange?(false)
            return
        }
        do {
            try pmset.restoreValues(backup)
            isActive = false
            onStateChange?(false)
            errorMessage = nil
        } catch ShellError.userCancelled {
            // Don't change state
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyCurrentSettings() {
        do {
            let enabled = SleepSetting.allCases.filter { settingStates[$0] == true }
            let disabled = SleepSetting.allCases.filter { settingStates[$0] != true }
            let backup = try? dependencies.backup.load()
            try pmset.applySettingsWithRestore(enabled, disabledSettings: disabled, backup: backup)
            errorMessage = nil
        } catch ShellError.userCancelled {
            // Revert toggle
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func persistSettingStates() {
        var dict: [String: Bool] = [:]
        for (setting, enabled) in settingStates {
            dict[setting.rawValue] = enabled
        }
        dependencies.preferences.set(dict, forKey: BenzoPreferenceKey.settingStates)
    }

    private func updateLaunchAtLogin() {
        do {
            if launchAtLogin {
                try dependencies.loginItem.register()
            } else {
                try dependencies.loginItem.unregister()
            }
        } catch {
            errorMessage = "Failed to update launch at login: \(error.localizedDescription)"
        }
    }
}
