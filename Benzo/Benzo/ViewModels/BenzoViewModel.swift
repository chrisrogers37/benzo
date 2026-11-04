import Combine
import Foundation

final class BenzoViewModel: ObservableObject {
    static let sleepUnavailableReason = "Sleep Now is unavailable while recovery controls are being updated."
    static let selectionEditBlockedReason = "Resolve the current session or recovery before changing settings."

    @Published var isActive: Bool {
        didSet { dependencies.preferences.set(isActive, forKey: BenzoPreferenceKey.isActive) }
    }
    @Published private(set) var settingStates: [SleepSetting: Bool] {
        didSet { persistSettingStates() }
    }
    @Published var launchAtLogin: Bool = false {
        didSet {
            guard isInitialized else { return }
            updateLaunchAtLogin()
        }
    }
    @Published private(set) var permissionObservation: PermissionObservation = .unknown("Not checked")
    @Published var showPermissionStatus = true
    @Published var errorMessage: String?

    // Diagnostics
    @Published var showDiagnostics = false
    @Published private(set) var sleepData: DiagnosticState<SleepReadPayload> = .idle
    @Published private(set) var usbDevices: DiagnosticState<[USBDevice]> = .idle
    @Published private(set) var observedSettings: DiagnosticState<[ObservedSetting]> = .idle
    private var diagnosticGeneration = 0

    var isLoadingDiagnostics: Bool {
        sleepData.isLoading || usbDevices.isLoading || observedSettings.isLoading
    }

    var onStateChange: ((Bool) -> Void)?
    private var isInitialized = false
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
            refreshPermissionObservation()
        }
    }

    func refreshPermissionObservation() {
        permissionObservation = dependencies.observePermission()
    }

    var activeCount: Int {
        settingStates.values.filter { $0 }.count
    }

    var isSelectionEditBlocked: Bool {
        dependencies.backup.evidencePresence() != .absent
    }

    func toggleMaster() {
        if isActive {
            deactivate()
        } else {
            activate()
        }
    }

    func toggleSetting(_ setting: SleepSetting) {
        guard !isActive, !isSelectionEditBlocked else {
            errorMessage = Self.selectionEditBlockedReason
            return
        }
        settingStates[setting]?.toggle()
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
        errorMessage = Self.sleepUnavailableReason
    }

    // MARK: - Diagnostics

    func loadDiagnostics() {
        // Called by the UI; all generation and published state access stays on its main boundary.
        diagnosticGeneration += 1
        let generation = diagnosticGeneration
        sleepData = .loading
        usbDevices = .loading
        observedSettings = .loading
        let dependencies = self.dependencies

        dependencies.runInBackground { [weak self] in
            let result = await dependencies.fetchSleepData()
            dependencies.runOnMain {
                guard let self, self.diagnosticGeneration == generation else { return }
                self.sleepData = DiagnosticState(result)
            }
        }
        dependencies.runInBackground { [weak self] in
            let result = await dependencies.fetchUSBDevices()
            dependencies.runOnMain {
                guard let self, self.diagnosticGeneration == generation else { return }
                self.usbDevices = DiagnosticState(result)
            }
        }
        dependencies.runInBackground { [weak self] in
            let result = await dependencies.readObservedSettings()
            dependencies.runOnMain {
                guard let self, self.diagnosticGeneration == generation else { return }
                self.observedSettings = DiagnosticState(result)
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
