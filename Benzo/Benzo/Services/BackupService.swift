import Foundation

struct BackupService: BackupStoring {
    let fileURL: URL
    let clock: any BenzoClock

    private var backupURL: URL {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        return fileURL
    }

    func hasBackup() -> Bool {
        FileManager.default.fileExists(atPath: backupURL.path)
    }

    func save(_ state: PMSetState) throws {
        let backup = OriginalSettingsBackup(values: state.values, capturedAt: clock.now)
        let data = try JSONEncoder().encode(backup)
        try data.write(to: backupURL, options: .atomic)
    }

    func load() throws -> OriginalSettingsBackup {
        let data = try Data(contentsOf: backupURL)
        return try JSONDecoder().decode(OriginalSettingsBackup.self, from: data)
    }
}
