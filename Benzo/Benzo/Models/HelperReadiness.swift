import Foundation

enum HelperUnavailableReason: Equatable, Sendable {
    case connection
    case incompatible
    case signingUnavailable
    case executionUncertain
}

/// Setup alone is not readiness: the live client must check the installed tool,
/// protocol compatibility, and access for the account using Benzo.
enum HelperReadiness: Equatable, Sendable {
    case checking
    case notInstalled
    case requiresApproval
    case needsOwnerAuthorization
    case ready
    case differentAccount
    case unavailable(HelperUnavailableReason)

    var title: String {
        switch self {
        case .checking: return "Checking Power Access"
        case .notInstalled, .requiresApproval, .needsOwnerAuthorization: return "Set Up Power Access"
        case .ready: return "Benzo Is Ready"
        case .differentAccount: return "Benzo Is Set Up for Another Account"
        case .unavailable(.connection): return "Power Access Is Unavailable"
        case .unavailable(.incompatible): return "Update Power Access"
        case .unavailable(.signingUnavailable): return "Setup Is Unavailable in This Build"
        case .unavailable(.executionUncertain): return "Power Settings Need Recovery"
        }
    }

    var message: String {
        switch self {
        case .checking: return "Checking this account’s access to power settings."
        case .notInstalled, .requiresApproval, .needsOwnerAuthorization:
            return "One administrator approval lets this Mac account apply and restore Benzo’s supported power settings. These settings affect everyone using this Mac."
        case .ready: return "This account can apply and restore settings. Turning Benzo on, off, or quitting needs no further administrator approval."
        case .differentAccount: return "Use the Mac account that completed setup. This account cannot change settings through Benzo."
        case .unavailable(.connection): return "Benzo couldn’t verify power access. Check again, or repair access after restoring any active settings."
        case .unavailable(.incompatible): return "The installed power tool needs an update. Restore any active settings before updating power access."
        case .unavailable(.signingUnavailable): return "This copy of Benzo is missing a usable power tool. Install a complete Benzo app, then try setup again."
        case .unavailable(.executionUncertain): return "An earlier settings change has not finished safely. Your recovery record is preserved. Check recovery before making further changes."
        }
    }

    var supportsRepair: Bool {
        self == .ready || self == .unavailable(.incompatible) || self == .unavailable(.connection)
    }
}

@MainActor
protocol HelperSetupClient {
    func refresh() async -> HelperReadiness
    func register() async throws -> HelperReadiness
    func replace() async throws -> HelperReadiness
    func remove() async throws -> HelperReadiness
    func authorizeCurrentAccount() async throws -> HelperReadiness
    func openApprovalSettings()
}
