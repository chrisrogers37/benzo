import Foundation
import Darwin

/// Checked account-local evidence storage. The stable flock coordinates Benzo instances;
/// ownership checks do not authenticate evidence against another process running as this user.
final class DurableJournal: RecoveryStoring {
    private let directory: URL
    private let uid: UInt32
    private let hostID: String
    private let beforeBoundary: (PersistenceBoundary) throws -> Void
    private var directoryFD: Int32 = -1
    private var parentFD: Int32 = -1
    private var lockFD: Int32 = -1
    private let journalName = "recovery-journal.json"
    private let previousName = "recovery-journal.previous.json"
    private let receiptName = "recovery-receipt.json"
    private let fenceName = "execution-fence.json"
    private let previousFenceName = "execution-fence.previous.json"
    private let journalMarker = "recovery-established"
    private let fenceMarker = "execution-established"
    private let completionMarker = "execution-completion-pending.json"
    private let lockName = "recovery.lock"
    private let legacyName = "original-pmset.json"
    private let maximumBytes = 1_048_576

    init(directory: URL, uid: UInt32, hostID: String,
         beforeBoundary: @escaping (PersistenceBoundary) throws -> Void = { _ in }) {
        self.directory = directory; self.uid = uid; self.hostID = hostID
        self.beforeBoundary = beforeBoundary
    }

    deinit {
        if lockFD >= 0 { _ = Darwin.close(lockFD) }
        if directoryFD >= 0 { _ = Darwin.close(directoryFD) }
        if parentFD >= 0 { _ = Darwin.close(parentFD) }
    }

    func acquireLock() throws {
        if lockFD >= 0 { try checkDirectoryIdentity(); return }
        guard uid == getuid(), UUID(uuidString: hostID) != nil, hostID.utf8.count == 36,
              directory.isFileURL, directory.path.hasPrefix("/"), directory.path != "/" else {
            throw invalid("Recovery storage identity or location is invalid.")
        }
        try openDirectory()
        let fd = openat(directoryFD, lockName, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { throw invalid("Recovery lock could not be opened safely.") }
        do {
            try validateFile(fd)
            guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
                throw invalid("Another Benzo instance may be controlling this account's settings. Close it before retrying.")
            }
            lockFD = fd
        } catch {
            _ = Darwin.close(fd)
            throw error
        }
    }

    func loadJournal() throws -> RecoveryJournal? {
        try requireLock()
        try rejectTemporaryEvidence()
        let marker = try readMarker(journalMarker)
        let current = try readJournal(journalName)
        let previous = try readJournal(previousName)
        let receipt = try readJournal(receiptName)
        let pendingCompletion = try readPendingCompletion()
        let hasFence = try readFile(fenceName) != nil || readFile(previousFenceName) != nil || readMarker(fenceMarker) || pendingCompletion != nil
        guard let current else {
            guard !marker, previous == nil, receipt == nil, !hasFence else {
                throw invalid("Current recovery evidence is missing. Existing evidence was preserved.")
            }
            return nil
        }
        guard marker else { throw invalid("Recovery generation evidence is missing.") }
        try validatePrevious(previous, current: current)
        if let receipt {
            guard receipt.resolvedAt != nil else { throw invalid("The recovery receipt is unresolved.") }
            if receipt.sessionID == current.sessionID {
                guard current == receipt else { throw invalid("The recovery receipt does not match current evidence.") }
            }
        }
        if current.resolvedAt != nil {
            guard receipt == current else { throw RecoveryEvidenceError.receiptRequired(current) }
        }
        return current
    }

    func commitJournal(_ journal: RecoveryJournal) throws {
        try requireLock()
        try rejectTemporaryEvidence()
        try journal.validate(uid: uid, hostID: hostID)
        let old = try readJournal(journalName)
        if let old {
            guard try readMarker(journalMarker) else { throw invalid("Recovery generation evidence is missing.") }
            try validatePrevious(try readJournal(previousName), current: old)
            if old.sessionID == journal.sessionID {
                guard old == journal || journal.revision > old.revision,
                      old.uid == journal.uid, old.hostID == journal.hostID,
                      old.capturedAt == journal.capturedAt, old.capture == journal.capture,
                      old.profiles == journal.profiles, old.selectedSettings == journal.selectedSettings,
                      zip(old.cells, journal.cells).allSatisfy({
                          $0.cell == $1.cell && $0.original == $1.original && ($0.owned || !$1.owned)
                      }), old.cells.count == journal.cells.count,
                      old.resolvedAt == nil || old == journal else {
                    throw invalid("Recovery originals or session history cannot be replaced.")
                }
            } else {
                guard old.resolvedAt != nil, try readJournal(receiptName) == old, journal.revision == 1 else {
                    throw invalid("A new session cannot replace unresolved recovery evidence.")
                }
            }
            if old != journal { try write(encode(old), named: previousName, renameBoundary: .previousRename) }
        } else {
            guard try loadJournal() == nil, journal.revision == 1 else {
                throw invalid("The first recovery generation is invalid.")
            }
            try write(markerData, named: journalMarker)
        }
        try write(encode(journal), named: journalName)
    }

    func saveResolvedReceipt(_ journal: RecoveryJournal) throws {
        try requireLock()
        try rejectTemporaryEvidence()
        try journal.validate(uid: uid, hostID: hostID)
        guard journal.resolvedAt != nil, try readJournal(journalName) == journal,
              try readMarker(journalMarker) else {
            throw invalid("Only the current resolved journal can become a recovery receipt.")
        }
        if let old = try readJournal(receiptName), old.resolvedAt == nil {
            throw invalid("Existing unresolved receipt evidence cannot be overwritten.")
        }
        try write(encode(journal), named: receiptName)
    }

    func loadFence() throws -> ExecutionFence? {
        try requireLock()
        try rejectTemporaryEvidence()
        let marker = try readMarker(fenceMarker)
        let current = try readFence(fenceName)
        let previous = try readFence(previousFenceName)
        let pendingCompletion = try readPendingCompletion()
        guard let current else {
            guard !marker, previous == nil, pendingCompletion == nil else { throw invalid("Current execution evidence is missing.") }
            return nil
        }
        guard marker, try readMarker(journalMarker), try readJournal(journalName) != nil else {
            throw invalid("Execution evidence is missing its recovery generation.")
        }
        // An unresolved predecessor may only be completed, never superseded by another launch.
        if let previous, !previous.completed, previous.bootID == current.bootID {
            guard sameRequest(previous, current) else {
                throw invalid("An unresolved execution fence was replaced by another request.")
            }
        }
        if let pendingCompletion {
            if pendingCompletion.bootID == current.bootID {
                guard sameRequest(pendingCompletion, current) else {
                    throw invalid("Incomplete completion evidence belongs to another request in this boot.")
                }
                // A visible completed rename is insufficient: the marker survives until every
                // file and directory durability check for that completion has succeeded.
                return pendingCompletion
            }
            guard !current.completed else {
                throw invalid("Completion evidence from another boot has not been reconciled.")
            }
        }
        return current
    }

    func commitFence(_ fence: ExecutionFence) throws {
        try requireLock()
        try rejectTemporaryEvidence()
        try fence.validate(uid: uid, hostID: hostID)
        guard let journal = try readJournal(journalName), journal.resolvedAt == nil,
              try readMarker(journalMarker), journal.sessionID == fence.sessionID,
              journal.operation?.id == fence.operationID, journal.operation?.bootID == fence.bootID,
              journal.operation?.steps.contains(where: { $0.cell == fence.cell && $0.target == fence.target && $0.phase == .intended }) == true else {
            throw invalid("Execution requires a matching durable journal intent.")
        }
        if let pendingCompletion = try readPendingCompletion(), pendingCompletion.bootID == fence.bootID {
            throw invalid("Completion persistence is uncertain in this boot. New execution is blocked.")
        }
        let old = try loadFence()
        if let old {
            if !old.completed && old.bootID == fence.bootID {
                guard sameRequest(old, fence), fence.completed || old == fence else {
                    throw invalid("Uncertain execution cannot be superseded by a new request.")
                }
            }
            if old == fence {
                // Retrying admission must repeat durability checks even when a pending rename
                // from an earlier failed commit is already visible.
                if !fence.completed { try write(encode(fence), named: fenceName) }
                return
            }
            try write(encode(old), named: previousFenceName, renameBoundary: .previousRename)
        } else {
            guard !fence.completed else { throw invalid("Completion requires an existing durable execution intent.") }
            try write(markerData, named: fenceMarker)
        }
        if fence.completed {
            guard let old, !old.completed, sameRequest(old, fence) else {
                throw invalid("Completion does not match the pending execution request.")
            }
            // Preserve uncertainty durably before any completed generation can become visible.
            // A marker from an older boot is retained until this replacement is fully durable.
            try write(encode(old), named: completionMarker)
            try write(encode(fence), named: fenceName)
            guard try readPendingCompletion() == old else {
                throw invalid("Pending completion evidence changed before finalization.")
            }
            try beforeBoundary(.completionMarkerRemove)
            guard unlinkat(directoryFD, completionMarker, 0) == 0 else {
                throw invalid("Durable completion could not remove its pending marker.")
            }
            // If cleanup fails after unlink, completion was already durable. A surviving marker
            // conservatively fences relaunch; absence cannot hide a failed completion write.
            try syncDirectory(directoryFD)
        } else {
            try write(encode(fence), named: fenceName)
        }
    }

    func loadLegacyEvidence() throws -> Data? {
        try requireLock()
        return try readFile(legacyName)
    }

    private var markerData: Data { Data("BENZO_RECOVERY_1\n\(uid)\n\(hostID)\n".utf8) }

    private func sameRequest(_ lhs: ExecutionFence, _ rhs: ExecutionFence) -> Bool {
        lhs.schema == rhs.schema && lhs.uid == rhs.uid && lhs.hostID == rhs.hostID &&
        lhs.bootID == rhs.bootID && lhs.incarnationID == rhs.incarnationID &&
        lhs.sessionID == rhs.sessionID && lhs.operationID == rhs.operationID &&
        lhs.cell == rhs.cell && lhs.target == rhs.target
    }

    private func validatePrevious(_ previous: RecoveryJournal?, current: RecoveryJournal) throws {
        guard let previous else {
            guard current.revision == 1 else { throw invalid("Previous recovery generation is missing.") }
            return
        }
        if previous.sessionID == current.sessionID {
            guard previous.revision <= current.revision, previous.capture == current.capture,
                  previous.capturedAt == current.capturedAt, previous.profiles == current.profiles,
                  previous.selectedSettings == current.selectedSettings,
                  previous.cells.map(\.cell) == current.cells.map(\.cell),
                  previous.cells.map(\.original) == current.cells.map(\.original) else {
                throw invalid("Recovery generations disagree about original settings.")
            }
        } else if previous.resolvedAt == nil {
            throw invalid("Previous unresolved recovery evidence cannot be replaced.")
        }
    }

    private func readJournal(_ name: String) throws -> RecoveryJournal? {
        guard let data = try readFile(name) else { return nil }
        let journal: RecoveryJournal = try decode(data)
        try journal.validate(uid: uid, hostID: hostID)
        return journal
    }

    private func readFence(_ name: String) throws -> ExecutionFence? {
        guard let data = try readFile(name) else { return nil }
        let fence: ExecutionFence = try decode(data)
        try fence.validate(uid: uid, hostID: hostID)
        return fence
    }

    private func readPendingCompletion() throws -> ExecutionFence? {
        guard let pending = try readFence(completionMarker) else { return nil }
        guard !pending.completed else { throw invalid("Pending completion evidence incorrectly claims completion.") }
        return pending
    }

    private func readMarker(_ name: String) throws -> Bool {
        guard let data = try readFile(name) else { return false }
        guard data == markerData else { throw invalid("Recovery generation marker is invalid.") }
        return true
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw invalid("Recovery evidence is malformed or unsupported. Original files were preserved.") }
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        guard data.count <= maximumBytes else { throw invalid("Recovery evidence exceeds its supported limit.") }
        return data
    }

    private func requireLock() throws {
        guard lockFD >= 0 else { throw invalid("Recovery storage has not acquired exclusive admission.") }
        try checkDirectoryIdentity()
        var held = stat(), named = stat()
        guard fstat(lockFD, &held) == 0, fstatat(directoryFD, lockName, &named, AT_SYMLINK_NOFOLLOW) == 0,
              held.st_dev == named.st_dev, held.st_ino == named.st_ino else {
            throw invalid("The stable recovery lock was replaced. Settings remain protected.")
        }
        try validateFile(lockFD)
    }

    private func openDirectory() throws {
        if directoryFD >= 0 { try checkDirectoryIdentity(); return }
        let components = directory.path.split(separator: "/").map(String.init)
        guard !components.isEmpty, !components.contains("."), !components.contains("..") else {
            throw invalid("Recovery storage location is invalid.")
        }
        var ancestor = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard ancestor >= 0 else { throw invalid("Recovery storage parents could not be inspected.") }
        do {
            var path = ""
            try validateParent(ancestor, path: "/")
            for component in components.dropLast() {
                let next = openat(ancestor, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard next >= 0 else { throw invalid("Recovery storage has an unsafe or inaccessible parent.") }
                do { try checkedClose(ancestor); ancestor = next }
                catch { _ = Darwin.close(next); throw error }
                path += "/" + component
                try validateParent(ancestor, path: path)
            }
            let name = components.last!
            var created = false
            if mkdirat(ancestor, name, mode_t(0o700)) == 0 { created = true }
            else if errno != EEXIST { throw invalid("Private recovery storage could not be created.") }
            let fd = openat(ancestor, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { throw invalid("Recovery storage is not a safe directory.") }
            do {
                try validateDirectory(fd)
                if created { try syncDirectory(ancestor) }
            } catch { _ = Darwin.close(fd); throw error }
            parentFD = ancestor; directoryFD = fd
        } catch { _ = Darwin.close(ancestor); throw error }
    }

    private func validateParent(_ fd: Int32, path: String) throws {
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR,
              info.st_uid == 0 || info.st_uid == uid else {
            throw invalid("Recovery storage has an untrusted parent directory.")
        }
        let safeTemporaryRoot = path == "/private/tmp" && info.st_uid == 0 && (info.st_mode & S_ISVTX) != 0
        guard (info.st_mode & 0o022) == 0 || safeTemporaryRoot else {
            throw invalid("Recovery storage has a writable parent directory.")
        }
    }

    private func validateDirectory(_ fd: Int32) throws {
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR,
              info.st_uid == uid, (info.st_mode & 0o7777) == 0o700 else {
            throw invalid("Recovery storage must be an account-owned private directory.")
        }
    }

    private func checkDirectoryIdentity() throws {
        guard directoryFD >= 0, parentFD >= 0 else { throw invalid("Recovery storage is unavailable.") }
        try validateDirectory(directoryFD)
        var held = stat(), named = stat()
        guard fstat(directoryFD, &held) == 0,
              fstatat(parentFD, directory.lastPathComponent, &named, AT_SYMLINK_NOFOLLOW) == 0,
              held.st_dev == named.st_dev, held.st_ino == named.st_ino,
              (named.st_mode & S_IFMT) == S_IFDIR else {
            throw invalid("Recovery storage was moved or replaced. Settings remain protected.")
        }
    }

    private func validateFile(_ fd: Int32) throws {
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == uid, info.st_nlink == 1, (info.st_mode & 0o7777) == 0o600,
              info.st_size >= 0, info.st_size <= maximumBytes else {
            throw invalid("Recovery evidence has unsafe ownership, permissions, type or size.")
        }
    }

    private func readFile(_ name: String) throws -> Data? {
        let fd = openat(directoryFD, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else {
            if errno == ENOENT { return nil }
            throw invalid("Recovery evidence could not be read safely.")
        }
        var isOpen = true
        defer { if isOpen { _ = Darwin.close(fd) } }
        try validateFile(fd)
        var original = stat()
        guard fstat(fd, &original) == 0 else { throw invalid("Recovery evidence metadata is unavailable.") }
        var data = Data()
        var bytes = [UInt8](repeating: 0, count: 8_192)
        while true {
            let count = Darwin.read(fd, &bytes, bytes.count)
            if count < 0 {
                if errno == EINTR { continue }
                throw invalid("Recovery evidence read failed.")
            }
            if count == 0 { break }
            guard data.count + count <= maximumBytes else { throw invalid("Recovery evidence is oversized.") }
            data.append(contentsOf: bytes.prefix(count))
        }
        var after = stat(), named = stat()
        guard fstat(fd, &after) == 0, fstatat(directoryFD, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
              original.st_dev == named.st_dev, original.st_ino == named.st_ino,
              original.st_size == after.st_size, data.count == after.st_size,
              original.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              original.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              original.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              original.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else {
            throw invalid("Recovery evidence changed while being read.")
        }
        try validateFile(fd)
        isOpen = false
        try checkedClose(fd)
        return data
    }

    private func rejectTemporaryEvidence() throws {
        let scanFD = openat(directoryFD, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard scanFD >= 0 else { throw invalid("Recovery generations could not be inspected.") }
        guard let stream = fdopendir(scanFD) else {
            _ = Darwin.close(scanFD)
            throw invalid("Recovery generations could not be inspected.")
        }
        var found = false
        errno = 0
        while let entry = readdir(stream) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(cString: $0) }
            }
            if name.hasPrefix(".benzo-") { found = true }
            errno = 0
        }
        let readError = errno
        let closeResult = closedir(stream)
        guard readError == 0, closeResult == 0 else { throw invalid("Recovery generations could not be inspected completely.") }
        guard !found else { throw invalid("An interrupted persistence operation needs recovery. Temporary evidence was preserved.") }
    }

    private func write(_ data: Data, named name: String, renameBoundary: PersistenceBoundary = .rename) throws {
        guard data.count <= maximumBytes else { throw invalid("Recovery evidence is oversized.") }
        let temporary = ".benzo-\(UUID().uuidString).tmp"
        let fd = openat(directoryFD, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { throw invalid("A private recovery generation could not be created.") }
        var isOpen = true
        defer { if isOpen { _ = Darwin.close(fd) } }
        try validateFile(fd)
        try beforeBoundary(.write)
        try data.withUnsafeBytes { buffer in
            var written = 0
            while written < buffer.count {
                let amount = Darwin.write(fd, buffer.baseAddress!.advanced(by: written), buffer.count - written)
                if amount < 0 && errno == EINTR { continue }
                guard amount > 0 else { throw invalid("Recovery evidence write failed.") }
                written += amount
            }
        }
        try beforeBoundary(.fileSync)
        guard fsync(fd) == 0 else { throw invalid("Recovery evidence file synchronization failed.") }
        try beforeBoundary(.fileFullSync)
        guard fcntl(fd, F_FULLFSYNC) == 0 else { throw invalid("Recovery evidence full synchronization failed.") }
        try beforeBoundary(.fileClose)
        isOpen = false
        try checkedClose(fd)
        try beforeBoundary(renameBoundary)
        guard renameat(directoryFD, temporary, directoryFD, name) == 0 else {
            throw invalid("Recovery generation replacement failed.")
        }
        try syncDirectory(directoryFD)
    }

    private func syncDirectory(_ fd: Int32) throws {
        let syncFD = openat(fd, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard syncFD >= 0 else { throw invalid("Recovery directory could not be opened for synchronization.") }
        var isOpen = true
        defer { if isOpen { _ = Darwin.close(syncFD) } }
        try beforeBoundary(.directorySync)
        guard fsync(syncFD) == 0 else { throw invalid("Recovery directory synchronization failed.") }
        try beforeBoundary(.directoryFullSync)
        guard fcntl(syncFD, F_FULLFSYNC) == 0 else { throw invalid("Recovery directory full synchronization failed.") }
        try beforeBoundary(.directoryClose)
        isOpen = false
        try checkedClose(syncFD)
    }

    private func checkedClose(_ fd: Int32) throws {
        guard Darwin.close(fd) == 0 else { throw invalid("Recovery evidence close failed.") }
    }

    private func invalid(_ message: String) -> RecoveryEvidenceError { .invalid(message) }
}
