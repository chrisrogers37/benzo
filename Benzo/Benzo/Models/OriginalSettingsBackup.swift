import Foundation

struct OriginalSettingsBackup: Codable {
    let values: [String: String]
    let capturedAt: Date
}
