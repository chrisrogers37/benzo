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
