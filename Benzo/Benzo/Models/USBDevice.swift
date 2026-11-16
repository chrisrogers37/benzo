import Foundation

/// system_profiler describes requirements or allocations, not measured power use.
enum USBPowerReport: Equatable {
    case requiredCurrent(milliamps: String)
    case allocatedPower(String)

    var label: String {
        switch self {
        case .requiredCurrent: return "Current required"
        case .allocatedPower: return "Power allocated"
        }
    }

    var value: String {
        switch self {
        case .requiredCurrent(let milliamps): return "\(milliamps) mA"
        case .allocatedPower(let reported): return reported
        }
    }
}

struct USBDevice: Identifiable {
    let id = UUID()
    let name: String
    let power: USBPowerReport?

    init(name: String, power: USBPowerReport? = nil) {
        self.name = name
        self.power = power
    }
}

/// Selected from the system's advertised data types, never inferred from an
/// exit-zero response: unsupported system_profiler requests can return empty JSON.
enum USBReportFormat: String, CaseIterable {
    case legacy = "SPUSBDataType"
    case host = "SPUSBHostDataType"

    var command: ReadCommand {
        switch self {
        case .legacy: return .usbDevices
        case .host: return .usbHostDevices
        }
    }
}
