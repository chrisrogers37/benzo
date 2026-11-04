import Foundation

struct BackupService: BackupStoring {
    let fileURL: URL
    let clock: any BenzoClock

    private var backupURL: URL {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        return fileURL
    }

    /// Inspect only metadata at the injected path. Corrupt or unreadable contents
    /// still count as evidence; an inconclusive lookup must not unlock editing.
    func evidencePresence() -> BackupEvidencePresence {
        guard fileURL.isFileURL else {
            return .unknown("Recovery evidence path is not a local file URL.")
        }
        var candidate = fileURL
        while true {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: candidate.path)
                if candidate.path == fileURL.path {
                    return .present
                }
                // ENOENT can also mean a dangling ancestor symlink. Only ordinary
                // missing components beneath a confirmed directory establish absence.
                guard attributes[.type] as? FileAttributeType == .typeDirectory else {
                    return .unknown("Recovery evidence parent is not a confirmed directory.")
                }
                return .absent
            } catch {
                let error = error as NSError
                let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
                guard error.domain == NSCocoaErrorDomain,
                      error.code == NSFileReadNoSuchFileError,
                      underlying == nil || (underlying?.domain == NSPOSIXErrorDomain && underlying?.code == Int(POSIXError.Code.ENOENT.rawValue)) else {
                    return .unknown(error.localizedDescription)
                }
            }
            let parent = candidate.deletingLastPathComponent()
            guard parent.path != candidate.path else {
                return .unknown("Recovery evidence parent could not be inspected.")
            }
            candidate = parent
        }
    }

    func hasBackup() -> Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    func save(_ state: PMSetState) throws {
        let backup = OriginalSettingsBackup(values: state.values, capturedAt: clock.now)
        let data = try JSONEncoder().encode(backup)
        try data.write(to: backupURL, options: .atomic)
    }

    func load() throws -> OriginalSettingsBackup {
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(OriginalSettingsBackup.self, from: data)
    }
}
