import Foundation

enum SleepSetting: String, CaseIterable, Identifiable {
    case hibernateMode
    case disablePowerNap
    case disableProximityWake
    case disableNetworkWake
    case disableTcpKeepAlive

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hibernateMode: return "Hibernate Mode"
        case .disablePowerNap: return "Disable Power Nap"
        case .disableTcpKeepAlive: return "Disable TCP Keep-Alive"
        case .disableProximityWake: return "Disable Proximity Wake"
        case .disableNetworkWake: return "Disable Network Wake"
        }
    }

    var description: String {
        switch self {
        case .hibernateMode: return "Requests hibernation; USB power-off is not guaranteed"
        case .disablePowerNap: return "Disables Power Nap where supported"
        case .disableTcpKeepAlive: return "Disables TCP keep-alives; may limit Find My during sleep"
        case .disableProximityWake: return "Requests no wake from nearby iPhone or Watch"
        case .disableNetworkWake: return "Disables Wake-on-LAN where supported"
        }
    }

    var defaultEnabled: Bool {
        switch self {
        case .hibernateMode, .disablePowerNap, .disableProximityWake, .disableNetworkWake:
            return true
        case .disableTcpKeepAlive:
            return false
        }
    }

    /// The pmset key-value pairs to set when this setting is enabled
    var pmsetCommands: [(key: String, value: String)] {
        switch self {
        case .hibernateMode:
            return [("hibernatemode", "25"), ("standby", "0"), ("autopoweroff", "0")]
        case .disablePowerNap:
            return [("powernap", "0")]
        case .disableTcpKeepAlive:
            return [("tcpkeepalive", "0")]
        case .disableProximityWake:
            return [("proximitywake", "0")]
        case .disableNetworkWake:
            return [("womp", "0")]
        }
    }

    /// All pmset keys this setting touches (used for backup/restore)
    var pmsetKeys: [String] {
        pmsetCommands.map(\.key)
    }
}
