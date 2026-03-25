import AppKit
import Foundation
import ServiceManagement

final class BenzoViewModel: ObservableObject {
    @Published var isActive: Bool {
        didSet { UserDefaults.standard.set(isActive, forKey: "isActive") }
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
    private var sleepTimer: Timer?

    init() {
        let savedActive = UserDefaults.standard.bool(forKey: "isActive")

        if let data = UserDefaults.standard.dictionary(forKey: "settingStates") as? [String: Bool] {
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

        if #available(macOS 13.0, *) {
            self.launchAtLogin = SMAppService.mainApp.status == .enabled
        }

        self.needsSetup = !ShellExecutor.isSetupComplete
        self.isInitialized = true
    }

    func runSetup() {
        do {
            try ShellExecutor.installSudoersRule()
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
        guard let backup = try? BackupService.load() else {
            errorMessage = "Nothing to revert — activate Benzo first."
            return
        }
        do {
            try PMSetService.restoreValues(backup)
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
        if isActive, let backup = try? BackupService.load() {
            try? PMSetService.restoreValues(backup)
        }
        NSApplication.shared.terminate(nil)
    }

    func sleepNow() {
        isSleeping = true
        errorMessage = nil

        do {
            // If Deep Sleep isn't active, enable it first
            if !isActive {
                if !BackupService.hasBackup() {
                    let state = try PMSetService.readCurrentState()
                    try BackupService.save(state)
                }
                let enabled = SleepSetting.allCases.filter { settingStates[$0] == true }
                try PMSetService.applySettings(enabled)
                isActive = true
                onStateChange?(true)
            }

            // Brief delay to let settings propagate, then sleep
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                do {
                    try PMSetService.sleepNow()
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
        let fireDate = Date().addingTimeInterval(seconds)
        sleepTimerRemaining = seconds

        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let remaining = fireDate.timeIntervalSinceNow
            if remaining <= 0 {
                timer.invalidate()
                self.sleepTimer = nil
                self.sleepTimerRemaining = nil
                self.executeSleepWithBlockerKill()
            } else {
                self.sleepTimerRemaining = remaining
            }
        }
    }

    func cancelScheduledSleep() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerRemaining = nil
    }

    private func executeSleepWithBlockerKill() {
        PMSetService.killCaffeinateProcesses()
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

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let currentState = try? PMSetService.readCurrentState() else { return }

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

            let blockers = DiagnosticService.fetchSleepBlockers()

            DispatchQueue.main.async {
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
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let (sessions, wakeReason) = DiagnosticService.fetchSleepData()
            let usb = DiagnosticService.fetchUSBDevices()

            DispatchQueue.main.async {
                guard let self else { return }
                self.sleepSessions = sessions
                self.lastWakeReason = wakeReason.map { SleepSession.humanReadableReason($0) }
                self.usbDevices = usb
                self.settingsVerification = DiagnosticService.verifySettings(
                    settingStates: self.settingStates,
                    isActive: self.isActive
                )
                self.isLoadingDiagnostics = false
            }
        }
    }

    // MARK: - Private

    private func activate() {
        do {
            // Backup current values on first activation
            if !BackupService.hasBackup() {
                let state = try PMSetService.readCurrentState()
                try BackupService.save(state)
            }

            let enabled = SleepSetting.allCases.filter { settingStates[$0] == true }
            try PMSetService.applySettings(enabled)
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
        guard let backup = try? BackupService.load() else {
            // No backup — just toggle off visually
            isActive = false
            onStateChange?(false)
            return
        }
        do {
            try PMSetService.restoreValues(backup)
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
            let backup = try? BackupService.load()
            try PMSetService.applySettingsWithRestore(enabled, disabledSettings: disabled, backup: backup)
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
        UserDefaults.standard.set(dict, forKey: "settingStates")
    }

    private func updateLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                errorMessage = "Failed to update launch at login: \(error.localizedDescription)"
            }
        }
    }
}
