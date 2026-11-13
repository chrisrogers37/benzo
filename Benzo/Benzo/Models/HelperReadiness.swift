import Foundation

enum HelperUnavailableReason: Equatable, Sendable {
    case connection
    case incompatible
    case signingUnavailable
    case executionUncertain
}

/// Registration alone is not readiness: the live client must also authenticate
/// the helper, check compatibility, and confirm ownership for the connected UID.
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
        case .checking: return "Checking Benzo Setup"
        case .notInstalled: return "Set Up Benzo"
        case .requiresApproval: return "Approve Benzo in System Settings"
        case .needsOwnerAuthorization: return "Authorize This Account"
        case .ready: return "Benzo Is Ready"
        case .differentAccount: return "Benzo Is Set Up for Another Account"
        case .unavailable(.connection): return "Benzo’s Helper Is Unavailable"
        case .unavailable(.incompatible): return "Benzo Needs a Matching Helper"
        case .unavailable(.signingUnavailable): return "Setup Is Unavailable in This Build"
        case .unavailable(.executionUncertain): return "Helper Recovery Required"
        }
    }

    var message: String {
        switch self {
        case .checking: return "Checking the helper and this account’s access."
        case .notInstalled: return "Set up Benzo’s helper to apply and restore power settings. Only this Mac account will be authorized."
        case .requiresApproval: return "Allow Benzo’s background helper in Login Items, then return here to finish setup."
        case .needsOwnerAuthorization: return "Authorize this Mac account to control Benzo. macOS may ask for an administrator password."
        case .ready: return "This account can apply and restore settings."
        case .differentAccount: return "Use the Mac account that completed setup. This account cannot change settings through Benzo."
        case .unavailable(.connection): return "Benzo couldn’t reach its helper. Check setup and try again."
        case .unavailable(.incompatible): return "Benzo’s bundled helper differs from the running helper. Replace it after resolving settings."
        case .unavailable(.signingUnavailable): return "Helper setup requires a signed, notarized Benzo release."
        case .unavailable(.executionUncertain): return "A previous settings request has unresolved execution evidence. Keep the recovery record; checking again does not authorize another write."
        }
    }
}

@MainActor
protocol HelperSetupClient {
    func refresh() async -> HelperReadiness
    func register() async throws -> HelperReadiness
    func replace() async throws -> HelperReadiness
    func authorizeCurrentAccount() async throws -> HelperReadiness
    func openApprovalSettings()
}
