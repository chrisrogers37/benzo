import Foundation

protocol CommandRunning {
    @discardableResult
    func runDirect(_ executable: String, _ arguments: [String]) throws -> String
    func runDirectWithSudo(_ executable: String, _ arguments: [String]) throws
}

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
    /// Load injected preferences/login state, but do not inspect or update permissions.
    case manual
}

/// Every boundary is supplied by the caller. Production composition belongs to AppDelegate;
/// there is deliberately no live factory or default dependency here.
struct BenzoDependencies {
    let commands: any CommandRunning
    let backup: any BackupStoring
    let preferences: any PreferenceStoring
    let loginItem: any LoginItemClient
    let observePermission: () -> PermissionObservation
    let fetchSleepData: () -> (sessions: [SleepSession], lastWakeReason: String?)
    let fetchUSBDevices: () -> [USBDevice]
    let verifySettings: ([SleepSetting: Bool], Bool) -> [SettingVerification]
    let runInBackground: (@escaping () -> Void) -> Void
    let runOnMain: (@escaping () -> Void) -> Void
    let terminate: () -> Void
}

enum BenzoPreferenceKey {
    static let isActive = "isActive"
    static let settingStates = "settingStates"
    static let sudoersRuleVersion = "sudoersRuleVersion"
}

enum BenzoPaths {
    static let pmset = "/usr/bin/pmset"
    static let sudo = "/usr/bin/sudo"
    // Canonical spelling of /etc/sudoers.d/benzo avoids following the standard /etc symlink.
    // Used only for metadata observation; no installer or remover consumes this path.
    static let sudoers = "/private/etc/sudoers.d/benzo"
    static let supportDirectory = "Benzo"
    static let backupFilename = "original-pmset.json"
}
