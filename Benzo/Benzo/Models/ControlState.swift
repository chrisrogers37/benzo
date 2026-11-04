import Foundation

enum ControlState: Equatable {
    case checking
    case off
    case applying
    case activeVerified(Date)
    case restoring
    case recoveryRequired(String)

    var isActive: Bool {
        if case .activeVerified = self { return true }
        return false
    }

    var isBusy: Bool {
        switch self {
        case .checking, .applying, .restoring: return true
        default: return false
        }
    }

    var title: String {
        switch self {
        case .checking: return "Checking Settings"
        case .off: return "Settings Are Off"
        case .applying: return "Applying Settings"
        case .activeVerified: return "Settings Applied"
        case .restoring: return "Restoring Settings"
        case .recoveryRequired: return "Recovery Required"
        }
    }

    var message: String {
        switch self {
        case .checking: return "Reading settings and recovery evidence."
        case .off: return "No unresolved Benzo settings session."
        case .applying: return "Applying your frozen selection and checking each value."
        case .activeVerified: return "Selected settings were read back successfully. Physical sleep behavior is not verified."
        case .restoring: return "Restoring captured pre-Benzo settings and checking each value."
        case .recoveryRequired(let reason): return reason
        }
    }
}

struct RecoveryConflict: Equatable, Identifiable {
    let cell: ManagedCell
    let original: Int
    let current: Int?
    let lastVerified: Int?
    var id: ManagedCell { cell }
}
