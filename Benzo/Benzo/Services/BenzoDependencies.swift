import Foundation

enum BackupEvidencePresence: Equatable {
    case absent
    case present
    case unknown(String)
}

protocol BackupStoring {
    func evidencePresence() -> BackupEvidencePresence
    func hasBackup() -> Bool
    func save(_ state: PMSetState) throws
    func load() throws -> OriginalSettingsBackup
}

protocol PreferenceStoring {
    func bool(forKey key: String) -> Bool
    func dictionary(forKey key: String) -> [String: Any]?
    func set(_ value: Any?, forKey key: String)
}

protocol BenzoClock {
    var now: Date { get }
}

enum BenzoStartupPolicy {
    case automatic
    /// Load injected preferences/login state without starting reconciliation or observations.
    case manual
}

/// Every boundary is supplied by the caller. Production composition belongs to AppDelegate;
/// there is deliberately no live factory or default dependency here.
struct BenzoDependencies {
    let coordinator: OperationCoordinator
    let preferences: any PreferenceStoring
    let loginItem: any LoginItemClient
    let helperSetup: any HelperSetupClient
    let observePermission: () -> PermissionObservation
    let fetchSleepData: () async -> Result<SleepReadPayload, DiagnosticReadError>
    let fetchUSBDevices: () async -> Result<[USBDevice], DiagnosticReadError>
    let readObservedSettings: () async -> Result<[ObservedSetting], DiagnosticReadError>
    let runInBackground: (@escaping () async -> Void) -> Void
    let runOnMain: (@escaping @MainActor () -> Void) -> Void
    let terminate: () -> Void
}

enum BenzoPreferenceKey {
    static let isActive = "isActive"
    static let settingStates = "settingStates"
    static let sudoersRuleVersion = "sudoersRuleVersion"
}

enum BenzoPaths {
    static let pmset = "/usr/bin/pmset"
    // Canonical spelling of /etc/sudoers.d/benzo avoids following the standard /etc symlink.
    // Used only for metadata observation; no installer or remover consumes this path.
    static let sudoers = "/private/etc/sudoers.d/benzo"
    static let supportDirectory = "Benzo"
    static let backupFilename = "original-pmset.json"
}
