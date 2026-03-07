import Foundation

enum BackupService {
    private static var backupURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let benzoDir = appSupport.appendingPathComponent("Benzo", isDirectory: true)
        try? FileManager.default.createDirectory(at: benzoDir, withIntermediateDirectories: true)
        return benzoDir.appendingPathComponent("original-pmset.json")
    }

    static func hasBackup() -> Bool {
        FileManager.default.fileExists(atPath: backupURL.path)
    }

    static func save(_ state: PMSetState) throws {
        let backup = OriginalSettingsBackup(values: state.values, capturedAt: Date())
        let data = try JSONEncoder().encode(backup)
        try data.write(to: backupURL, options: .atomic)
    }

    static func load() throws -> OriginalSettingsBackup {
        let data = try Data(contentsOf: backupURL)
        return try JSONDecoder().decode(OriginalSettingsBackup.self, from: data)
    }
}
