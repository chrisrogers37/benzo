import Combine
import Foundation

@MainActor
final class BenzoViewModel: ObservableObject {
    static let sleepUnavailableReason = "Sleep Now is unavailable for this manual apply-and-restore workflow."
    static let selectionEditBlockedReason = "Resolve the current session or recovery before changing settings."

    @Published private(set) var controlState: ControlState = .checking
    @Published private(set) var conflicts: [RecoveryConflict] = []
    @Published private(set) var unavailableSettings: [SleepSetting: String] = [:]
    @Published private(set) var executionUncertain = false
    @Published private(set) var hasSession = false
    @Published private(set) var frozenSettings: [SleepSetting]?
    @Published private(set) var capturedAt: Date?
    @Published private(set) var settingStates: [SleepSetting: Bool]
    @Published var launchAtLogin = false {
        didSet {
            guard isInitialized else { return }
            updateLaunchAtLogin()
        }
    }
    @Published private(set) var permissionObservation: PermissionObservation = .unknown("Not checked")
    @Published var showPermissionStatus = true
    @Published var errorMessage: String?

    @Published var showDiagnostics = false
    @Published private(set) var sleepData: DiagnosticState<SleepReadPayload> = .idle
    @Published private(set) var usbDevices: DiagnosticState<[USBDevice]> = .idle
    @Published private(set) var observedSettings: DiagnosticState<[ObservedSetting]> = .idle
    private var diagnosticGeneration = 0
    private var isInitialized = false
    private let dependencies: BenzoDependencies
    private(set) var startupTask: Task<Void, Never>?
    var onStateChange: ((ControlState) -> Void)?

    init(dependencies: BenzoDependencies, startupPolicy: BenzoStartupPolicy) {
        self.dependencies = dependencies
        let saved = dependencies.preferences.dictionary(forKey: BenzoPreferenceKey.settingStates) as? [String: Bool]
        settingStates = Dictionary(uniqueKeysWithValues: SleepSetting.allCases.map {
            ($0, saved?[$0.rawValue] ?? $0.defaultEnabled)
        })
        launchAtLogin = dependencies.loginItem.isEnabled
        isInitialized = true
        dependencies.coordinator.onChange = { [weak self] in self?.publishControlState() }
        publishControlState()
        if startupPolicy == .automatic {
            refreshPermissionObservation()
            startupTask = Task { [weak self] in await self?.reconcile() }
        }
    }

    var isActive: Bool { controlState.isActive }
    var isLoadingDiagnostics: Bool { sleepData.isLoading || usbDevices.isLoading || observedSettings.isLoading }
    var isSelectionEditBlocked: Bool { controlState != .off }
    var activeCount: Int { frozenSettings?.count ?? selectedSettings.count }
    var canToggleMaster: Bool { (controlState == .off && activeCount > 0) || isActive }
    var canRestore: Bool { hasSession && !controlState.isBusy && !executionUncertain && conflicts.isEmpty }

    // Eligibility is observed before a session is admitted. Stored choices are not proof of support.
    private var selectedSettings: [SleepSetting] {
        SleepSetting.allCases.filter { settingStates[$0] == true && unavailableSettings[$0] == nil }
    }

    func isSelected(_ setting: SleepSetting) -> Bool {
        if let frozenSettings { return frozenSettings.contains(setting) }
        return settingStates[setting] == true && unavailableSettings[setting] == nil
    }

    func refreshPermissionObservation() { permissionObservation = dependencies.observePermission() }

    func reconcile() async { await dependencies.coordinator.reconcile() }

    func toggleMaster() async {
        errorMessage = nil
        if isActive { await dependencies.coordinator.restore() }
        else if controlState == .off { await dependencies.coordinator.apply(settings: selectedSettings) }
    }

    func toggleSetting(_ setting: SleepSetting) {
        guard dependencies.coordinator.mayEditSelections() else {
            errorMessage = Self.selectionEditBlockedReason
            return
        }
        guard unavailableSettings[setting] == nil else {
            errorMessage = unavailableSettings[setting]
            return
        }
        settingStates[setting] = !(settingStates[setting] ?? false)
        dependencies.preferences.set(Dictionary(uniqueKeysWithValues: settingStates.map { ($0.key.rawValue, $0.value) }),
                                     forKey: BenzoPreferenceKey.settingStates)
        errorMessage = nil
    }

    func revertToDefaults() async {
        errorMessage = nil
        await dependencies.coordinator.restore()
    }

    func resolveConflict(_ conflict: RecoveryConflict, choice: ConflictChoice) async {
        await dependencies.coordinator.resolveConflict(conflict.cell, choice: choice)
    }

    func prepareToQuit() async -> Bool { await dependencies.coordinator.prepareToQuit() }

    // AppKit owns the terminateLater / Retry / Stay Open / Quit Anyway decision.
    func quit() { dependencies.terminate() }
    func sleepNow() { errorMessage = Self.sleepUnavailableReason }

    func loadDiagnostics() {
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

    private func publishControlState() {
        controlState = dependencies.coordinator.state
        conflicts = dependencies.coordinator.conflicts
        unavailableSettings = dependencies.coordinator.unavailable
        executionUncertain = dependencies.coordinator.executionUncertain
        hasSession = dependencies.coordinator.hasSession
        frozenSettings = dependencies.coordinator.frozenSettings
        capturedAt = dependencies.coordinator.capturedAt
        onStateChange?(controlState)
    }

    private func updateLaunchAtLogin() {
        do {
            if launchAtLogin { try dependencies.loginItem.register() }
            else { try dependencies.loginItem.unregister() }
        } catch {
            errorMessage = "Failed to update launch at login: \(error.localizedDescription)"
        }
    }
}
