import Foundation

enum ShellError: LocalizedError {
    case userCancelled
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .userCancelled:
            return "Authentication was cancelled."
        case .executionFailed(let message):
            return message
        }
    }
}

struct ObservedSetting: Identifiable, Equatable {
    var id: String { key }
    let key: String
    let actualValue: String?

    var displayName: String {
        switch key {
        case "hibernatemode": return "Hibernation mode"
        case "standby": return "Standby"
        case "autopoweroff": return "Automatic power-off"
        case "powernap": return "Power Nap"
        case "proximitywake": return "Proximity wake"
        case "womp": return "Wake for network access"
        case "tcpkeepalive": return "TCP keep-alive"
        default: return key
        }
    }

    var displayValue: String {
        guard let actualValue else { return "Not reported" }
        if key == "hibernatemode" {
            switch actualValue {
            case "0": return "Standard sleep"
            case "3": return "Safe sleep"
            case "25": return "Hibernate"
            default: return "Mode \(actualValue)"
            }
        }
        if ["standby", "autopoweroff", "powernap", "proximitywake", "womp", "tcpkeepalive"].contains(key) {
            if actualValue == "0" { return "Off" }
            if actualValue == "1" { return "On" }
        }
        return actualValue
    }

    // Retain the exact reported value without implying a hardware outcome.
    var rawDetail: String {
        actualValue.map { "\(key) = \($0)" } ?? key
    }
}

struct SleepReadPayload {
    let sessions: [SleepSession]
    let lastWakeReason: String?
}

enum DiagnosticReadError: Error {
    case commandFailed(CommandOutcome)
    case incompleteCapture(CommandOutcome)
    case unsupportedFormat
    case malformedFormat
}

enum DiagnosticState<Value> {
    case idle
    case loading
    case success(Value)
    case failure(DiagnosticReadError)

    init(_ result: Result<Value, DiagnosticReadError>) {
        switch result {
        case .success(let value): self = .success(value)
        case .failure(let error): self = .failure(error)
        }
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}
