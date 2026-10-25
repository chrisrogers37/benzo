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

struct SleepBlocker: Identifiable {
    let id = UUID()
    let processName: String
    let displayName: String
}

struct SettingVerification: Identifiable {
    let id = UUID()
    let setting: SleepSetting
    let key: String
    let expectedValue: String
    let actualValue: String
    let matches: Bool
}
