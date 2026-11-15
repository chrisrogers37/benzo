import Combine
import Foundation

@MainActor
final class BenzoViewModel: ObservableObject {
    static let sleepUnavailableReason = "Apply your selected settings before using Sleep Now."
    static let selectionEditBlockedReason = "Resolve the current session or recovery before changing settings."
    static let helperAccessRequiredReason = "Power access is needed to change settings. Open Power Access to complete setup."
    static let helperRecoveryReason = "Settings may still be changed. Power access is needed to restore them. Your recovery record is retained."
    static let helperReplacementBlockedReason = "Turn Benzo off and resolve any recovery before updating power access. If this copy cannot restore settings, use the previous Benzo release."
    static let helperRemovalBlockedReason = "Turn Benzo off and resolve any recovery before removing power access."
    static let helperSetupInProgressReason = "Finish power access setup before changing settings or quitting Benzo."
    static let quitInProgressReason = "Benzo is preparing to quit. Wait for restoration to finish."

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
            guard !isPreparingToQuit else {
                // @Published reenters didSet on assignment; suppress that nested
                // observer while putting the displayed preference back.
                isInitialized = false
                launchAtLogin = oldValue
                isInitialized = true
                return
            }
            updateLaunchAtLogin()
        }
    }
    @Published private(set) var helperReadiness: HelperReadiness = .checking
    @Published private(set) var isRefreshingHelper = false
    @Published private(set) var isPerformingHelperSetup = false
    @Published private(set) var isPreparingToQuit = false
    @Published private(set) var helperSetupError: String?
    @Published var showHelperSetup = false {
        didSet { if showHelperSetup { cancelScheduledSleep() } }
    }
    @Published private(set) var sleepRemainingSeconds: Int?
    @Published private(set) var sleepMessage: String?
    @Published private(set) var sleepRequestInFlight = false
    @Published private(set) var supportsSleep = false
    @Published var errorMessage: String?

    @Published var showDiagnostics = false
    @Published private(set) var sleepData: DiagnosticState<SleepReadPayload> = .idle
    @Published private(set) var usbDevices: DiagnosticState<[USBDevice]> = .idle
    @Published private(set) var observedSettings: DiagnosticState<[ObservedSetting]> = .idle
    private var diagnosticGeneration = 0
    private var refreshHelperAgain = false
    private var isInitialized = false
    private let dependencies: BenzoDependencies
    private let sleepCountdown: SleepCountdown
    private var sleepGeneration: UInt64 = 0
    private var sleepAdmissionInProgress = false
    private var lastCoordinatorSleepMessage: String?
    private(set) var sleepTask: Task<Void, Never>?
    private(set) var startupTask: Task<Void, Never>?
    var onStateChange: ((ControlState) -> Void)?

    init(dependencies: BenzoDependencies, startupPolicy: BenzoStartupPolicy) {
        self.dependencies = dependencies
        sleepCountdown = SleepCountdown(scheduler: dependencies.sleepScheduler)
        let saved = dependencies.preferences.dictionary(forKey: BenzoPreferenceKey.settingStates) as? [String: Bool]
        settingStates = Dictionary(uniqueKeysWithValues: SleepSetting.allCases.map {
            ($0, saved?[$0.rawValue] ?? $0.defaultEnabled)
        })
        launchAtLogin = dependencies.loginItem.isEnabled
        isInitialized = true
        sleepCountdown.onChange = { [weak self] in self?.sleepRemainingSeconds = $0 }
        sleepCountdown.onFire = { [weak self] in self?.sleepNow() }
        dependencies.coordinator.onChange = { [weak self] in self?.publishControlState() }
        publishControlState()
        if startupPolicy == .automatic {
            startupTask = Task { [weak self] in await self?.reconcile() }
        }
    }

    var isActive: Bool { controlState.isActive }
    var isLoadingDiagnostics: Bool { sleepData.isLoading || usbDevices.isLoading || observedSettings.isLoading }
    var isSelectionEditBlocked: Bool { controlState != .off || isPreparingToQuit }
    var activeCount: Int { frozenSettings?.count ?? selectedSettings.count }
    var hasHelperAccess: Bool { helperReadiness == .ready && !isPerformingHelperSetup && !isPreparingToQuit }
    var canToggleMaster: Bool { !sleepRequestInFlight && hasHelperAccess && ((controlState == .off && activeCount > 0) || isActive) }
    var canRestore: Bool { !sleepRequestInFlight && hasHelperAccess && hasSession && !controlState.isBusy && !executionUncertain && conflicts.isEmpty }
    var canReplaceHelper: Bool {
        helperReadiness.supportsRepair && canChangeHelperInstallation
    }
    var canRemoveHelper: Bool {
        (helperReadiness == .ready || helperReadiness == .unavailable(.incompatible)) && canChangeHelperInstallation
    }
    private var canChangeHelperInstallation: Bool {
        controlState == .off && !hasSession &&
            !executionUncertain && !sleepRequestInFlight && !isPerformingHelperSetup && !isRefreshingHelper && !isPreparingToQuit
    }

    var needsSleepAccessUpdate: Bool { helperReadiness == .ready && !supportsSleep }
    private var sleepEligibility: Bool {
        helperReadiness == .ready && supportsSleep && controlState.isActive && hasSession &&
            !executionUncertain && conflicts.isEmpty && !isPerformingHelperSetup &&
            !isRefreshingHelper && !isPreparingToQuit && !showHelperSetup
    }
    var canSleep: Bool { sleepEligibility && !sleepRequestInFlight && dependencies.coordinator.canAdmitSleep }
    var sleepDisabledReason: String? {
        if sleepRequestInFlight { return "The sleep request is pending. Refresh recovery to check its result." }
        if isPreparingToQuit { return Self.quitInProgressReason }
        if isPerformingHelperSetup || showHelperSetup { return Self.helperSetupInProgressReason }
        if isRefreshingHelper { return "Wait for Power Access to finish checking." }
        if needsSleepAccessUpdate { return "Turn Benzo off, then use Update Power Access to enable Sleep Now for this Mac account." }
        if helperReadiness != .ready { return Self.helperAccessRequiredReason }
        if executionUncertain || !conflicts.isEmpty { return "Resolve recovery before using Sleep Now." }
        if !controlState.isActive { return Self.sleepUnavailableReason }
        return nil
    }

    func scheduleSleep(minutes: Int) {
        guard canSleep, SleepCountdown.presets.contains(minutes) else { return }
        sleepGeneration &+= 1
        sleepMessage = nil
        sleepCountdown.start(minutes: minutes)
    }

    func cancelScheduledSleep() {
        sleepGeneration &+= 1
        let wasScheduled = sleepRemainingSeconds != nil
        sleepCountdown.cancel()
        if wasScheduled { sleepMessage = "Sleep timer canceled." }
    }

    func sleepNow() {
        guard canSleep else { errorMessage = sleepDisabledReason; return }
        cancelScheduledSleep()
        let generation = sleepGeneration
        sleepAdmissionInProgress = true
        sleepRequestInFlight = true
        sleepMessage = nil
        sleepTask = Task { [weak self] in
            guard let self else { return }
            await self.dependencies.coordinator.requestSleep {
                self.sleepGeneration == generation && self.sleepEligibility
            }
            self.sleepAdmissionInProgress = false
            self.publishControlState()
        }
    }

    func systemWillSleep() { cancelScheduledSleep() }
    func systemDidWake() {
        cancelScheduledSleep()
        Task { [weak self] in
            guard let self else { return }
            await self.dependencies.coordinator.waitUntilIdle()
            await self.reconcile()
        }
    }

    // Eligibility is observed before a session is admitted. Stored choices are not proof of support.
    private var selectedSettings: [SleepSetting] {
        SleepSetting.allCases.filter { settingStates[$0] == true && unavailableSettings[$0] == nil }
    }

    func isSelected(_ setting: SleepSetting) -> Bool {
        if let frozenSettings { return frozenSettings.contains(setting) }
        return settingStates[setting] == true && unavailableSettings[setting] == nil
    }

    func refreshHelperReadiness() async {
        if isRefreshingHelper {
            refreshHelperAgain = true
            return
        }
        sleepGeneration &+= 1
        isRefreshingHelper = true
        defer {
            isRefreshingHelper = false
            if !sleepEligibility { cancelScheduledSleep() }
        }
        // Keep the previous observation visible while refreshing. The write
        // transport independently checks authority at admission. If an operation
        // settles during the read, check again after the older response arrives.
        repeat {
            refreshHelperAgain = false
            helperReadiness = await dependencies.helperSetup.refresh()
            supportsSleep = dependencies.helperSetup.supportsSleep
        } while refreshHelperAgain
    }

    func registerHelper() async {
        guard helperReadiness == .notInstalled || helperReadiness == .requiresApproval else { return }
        await performHelperSetup { try await self.dependencies.helperSetup.register() }
    }

    func authorizeCurrentAccount() async {
        guard helperReadiness == .needsOwnerAuthorization else { return }
        await performHelperSetup { try await self.dependencies.helperSetup.authorizeCurrentAccount() }
    }

    func replaceHelper() async {
        guard canReplaceHelper else { return }
        await performHelperSetup { try await self.dependencies.helperSetup.replace() }
    }

    func removeHelper() async {
        guard canRemoveHelper else { return }
        await performHelperSetup { try await self.dependencies.helperSetup.remove() }
    }

    func openHelperApprovalSettings() {
        guard helperReadiness == .requiresApproval, !isPerformingHelperSetup, !isPreparingToQuit else { return }
        dependencies.helperSetup.openApprovalSettings()
    }

    private func performHelperSetup(_ action: () async throws -> HelperReadiness) async {
        guard !isPerformingHelperSetup, !isRefreshingHelper, !isPreparingToQuit else { return }
        cancelScheduledSleep()
        isPerformingHelperSetup = true
        helperSetupError = nil
        defer { isPerformingHelperSetup = false }
        do { _ = try await action() }
        catch { helperSetupError = error.localizedDescription }
        // Setup returning successfully is not evidence that power access is ready.
        await refreshHelperReadiness()
    }

    func reconcile() async {
        await dependencies.coordinator.reconcile()
        await refreshHelperReadiness()
    }

    private func requireHelperAccess() -> Bool {
        guard !isPreparingToQuit else {
            errorMessage = Self.quitInProgressReason
            return false
        }
        guard !isPerformingHelperSetup else {
            errorMessage = Self.helperSetupInProgressReason
            return false
        }
        guard hasHelperAccess else {
            errorMessage = hasSession ? Self.helperRecoveryReason : Self.helperAccessRequiredReason
            return false
        }
        return true
    }

    func toggleMaster() async {
        cancelScheduledSleep()
        errorMessage = nil
        guard requireHelperAccess() else { return }
        if sleepAdmissionInProgress || dependencies.coordinator.sleepRequestInFlight {
            await dependencies.coordinator.waitUntilIdle()
            guard requireHelperAccess() else { return }
        }
        if isActive { await dependencies.coordinator.restore() }
        else if controlState == .off { await dependencies.coordinator.apply(settings: selectedSettings) }
        await refreshHelperReadiness()
    }

    func toggleSetting(_ setting: SleepSetting) {
        guard !isPreparingToQuit else { errorMessage = Self.quitInProgressReason; return }
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
        cancelScheduledSleep()
        guard !isPreparingToQuit else { errorMessage = Self.quitInProgressReason; return }
        if sleepAdmissionInProgress || dependencies.coordinator.sleepRequestInFlight {
            await dependencies.coordinator.waitUntilIdle()
            guard !isPreparingToQuit else { errorMessage = Self.quitInProgressReason; return }
        }
        errorMessage = nil
        guard !hasSession || requireHelperAccess() else { return }
        await dependencies.coordinator.restore()
        await refreshHelperReadiness()
    }

    func resolveConflict(_ conflict: RecoveryConflict, choice: ConflictChoice) async {
        cancelScheduledSleep()
        guard !isPreparingToQuit else { errorMessage = Self.quitInProgressReason; return }
        if choice == .restoreOriginal, !requireHelperAccess() { return }
        await dependencies.coordinator.resolveConflict(conflict.cell, choice: choice)
        await refreshHelperReadiness()
    }

    func prepareToQuit() async -> Bool {
        cancelScheduledSleep()
        guard !isPreparingToQuit else { return false }
        guard !isPerformingHelperSetup else {
            errorMessage = Self.helperSetupInProgressReason
            return false
        }
        // An operation already in flight remains owned by the coordinator.
        if !controlState.isBusy && hasSession && !requireHelperAccess() { return false }
        // Keep admission closed after the coordinator restores Off, through the
        // AppKit termination reply. A new apply or helper lifecycle action must
        // never race a successful quit decision across an actor suspension.
        isPreparingToQuit = true
        let mayQuit = await dependencies.coordinator.prepareToQuit()
        if !mayQuit {
            await refreshHelperReadiness()
            isPreparingToQuit = false
        }
        return mayQuit
    }

    // AppKit owns the terminateLater / Retry / Stay Open / Quit Anyway decision.
    func quit() { dependencies.terminate() }

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
        sleepRequestInFlight = sleepAdmissionInProgress || dependencies.coordinator.sleepRequestInFlight
        if dependencies.coordinator.sleepMessage != lastCoordinatorSleepMessage {
            lastCoordinatorSleepMessage = dependencies.coordinator.sleepMessage
            if let message = lastCoordinatorSleepMessage { sleepMessage = message }
        }
        if !sleepEligibility && !sleepAdmissionInProgress { cancelScheduledSleep() }
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
