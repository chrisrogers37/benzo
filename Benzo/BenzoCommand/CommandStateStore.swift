import Darwin
import Foundation

enum PowerCommandStoreError: LocalizedError {
    case unsafeEvidence(String)
    var errorDescription: String? {
        if case .unsafeEvidence(let detail) = self {
            return "Benzo's command evidence needs administrator recovery. " + detail
        }
        return nil
    }
}

enum PowerCommandStoreBoundary: CaseIterable {
    case write, fileSync, fileFullSync, fileClose, rename
    case directorySync, directoryFullSync, pendingRemove
}

/// Fixed-path root authority. All access is descriptor-relative and the stable
/// exclusive lock is held through capture, execution, and terminal publication.
/// Existing missing/malformed evidence never becomes a fresh installation.
final class PowerCommandStore: PowerCommandStoring {
    static let path = "/private/var/db/com.benzo.command"
    static let directoryName = "com.benzo.command"
    static let stateName = "authority.json"
    static let lockName = "authority.lock"
    private static let pendingName = "commit-pending.json"
    private static let maximumBytes = 16_384

    private var parentFD: Int32 = -1
    private var directoryFD: Int32 = -1
    private var lockFD: Int32 = -1
    private let expectedUID: UInt32
    private let beforeBoundary: (PowerCommandStoreBoundary) throws -> Void

    convenience init() throws { try self.init(initialState: nil) }

    /// Setup holds the returned store alive through binary/policy publication.
    /// This never replaces or repairs existing state, even for the same account.
    static func installInitialState(_ state: PowerCommandState) throws -> PowerCommandStore {
        try state.validate()
        guard state.highWaterMark == 0, state.pending == nil else {
            throw invalid("Initial installation cannot fabricate execution history.")
        }
        return try PowerCommandStore(initialState: state)
    }

    private init(initialState: PowerCommandState?) throws {
        expectedUID = 0
        beforeBoundary = { _ in }
        guard geteuid() == 0, getuid() == 0 else {
            throw Self.invalid("Command authority can only be opened as root.")
        }
        do {
            let created = try openDirectory(creating: initialState != nil)
            try acquireLock(creating: created)
            if let initialState { try publish(encode(initialState), named: Self.stateName) }
            _ = try load()
        } catch { closeDescriptors(); throw error }
    }

#if BENZO_STORAGE_TESTS
    /// Test-target-only entry point: current-UID private fixtures, never the
    /// production path or root identity. Supplying initialState creates once.
    init(testingParentDirectory: URL, initialState: PowerCommandState? = nil,
         beforeBoundary: @escaping (PowerCommandStoreBoundary) throws -> Void = { _ in }) throws {
        expectedUID = getuid()
        self.beforeBoundary = beforeBoundary
        guard expectedUID != 0, geteuid() == expectedUID, testingParentDirectory.isFileURL,
              testingParentDirectory.standardizedFileURL.path != "/private/var/db" else {
            throw Self.invalid("Storage fixtures require an unprivileged private temporary parent.")
        }
        do {
            if let initialState {
                try initialState.validate()
                guard initialState.highWaterMark == 0, initialState.pending == nil else {
                    throw Self.invalid("Fixture initialization must start with an empty grant.")
                }
            }
            parentFD = Darwin.open(testingParentDirectory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard parentFD >= 0 else { throw Self.invalid("The private fixture parent is inaccessible.") }
            try validateParent(parentFD)
            let created: Bool
            if initialState != nil {
                guard mkdirat(parentFD, Self.directoryName, mode_t(0o700)) == 0 else {
                    throw Self.invalid("Fixture authority already exists or cannot be initialized.")
                }
                created = true
            } else { created = false }
            directoryFD = openat(parentFD, Self.directoryName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard directoryFD >= 0 else { throw Self.invalid("The private fixture directory is unsafe.") }
            try validateDirectory(directoryFD)
            if created { try synchronize(parentFD) }
            try acquireLock(creating: created)
            if let initialState { try publish(encode(initialState), named: Self.stateName) }
            _ = try load()
        } catch { closeDescriptors(); throw error }
    }
#endif

    deinit { closeDescriptors() }

    func load() throws -> PowerCommandState {
        try requireLock()
        try rejectInterruptedCommit()
        guard let bytes = try read(Self.stateName) else {
            throw Self.invalid("The established command authority is missing.")
        }
        let state: PowerCommandState
        do { state = try JSONDecoder().decode(PowerCommandState.self, from: bytes) }
        catch { throw Self.invalid("The command authority is malformed or unsupported.") }
        try state.validate()
        return state
    }

    func commit(_ state: PowerCommandState) throws {
        let old = try load()
        try state.validateTransition(from: old)
        if state == old { return }
        // A durable old-generation marker prevents a failed post-rename sync
        // from being mistaken for terminal proof after restart. Every leftover
        // marker/temp file fences further access; none is silently discarded.
        try publish(encode(old), named: Self.pendingName)
        try publish(encode(state), named: Self.stateName)
        try beforeBoundary(.pendingRemove)
        guard unlinkat(directoryFD, Self.pendingName, 0) == 0 else {
            throw Self.invalid("The committed command generation could not be finalized.")
        }
        try synchronize(directoryFD)
    }

    private func openDirectory(creating: Bool) throws -> Bool {
        var ancestor = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard ancestor >= 0 else { throw Self.invalid("The trusted storage path is inaccessible.") }
        do {
            try validateParent(ancestor)
            for component in ["private", "var", "db"] {
                let next = openat(ancestor, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard next >= 0 else { throw Self.invalid("The trusted storage path is unsafe.") }
                do { try validateParent(next) }
                catch { _ = Darwin.close(next); throw error }
                _ = Darwin.close(ancestor)
                ancestor = next
            }
            let created: Bool
            if creating {
                guard mkdirat(ancestor, Self.directoryName, mode_t(0o700)) == 0 else {
                    throw Self.invalid("Command authority already exists or cannot be initialized. It was not replaced.")
                }
                created = true
            } else { created = false }
            let opened = openat(ancestor, Self.directoryName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard opened >= 0 else { throw Self.invalid("The command storage path is not a safe directory.") }
            do {
                try validateDirectory(opened)
                if created { try synchronize(ancestor) }
            } catch { _ = Darwin.close(opened); throw error }
            parentFD = ancestor
            directoryFD = opened
            return created
        } catch {
            _ = Darwin.close(ancestor)
            throw error
        }
    }

    private func acquireLock(creating: Bool) throws {
        let flags = O_RDWR | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC | (creating ? O_CREAT | O_EXCL : 0)
        let opened = openat(directoryFD, Self.lockName, flags, mode_t(0o600))
        guard opened >= 0 else { throw Self.invalid("The established command lock is missing or unsafe.") }
        do {
            try validateFile(opened)
            guard flock(opened, LOCK_EX | LOCK_NB) == 0 else {
                throw Self.invalid("Another command instance holds admission.")
            }
            if creating {
                try synchronize(opened)
                try synchronize(directoryFD)
            }
            lockFD = opened
        } catch { _ = Darwin.close(opened); throw error }
    }

    private func requireLock() throws {
        guard lockFD >= 0, directoryFD >= 0, parentFD >= 0 else {
            throw Self.invalid("The command has not acquired exclusive admission.")
        }
        try validateParent(parentFD)
        try validateDirectory(directoryFD)
        try validateFile(lockFD)
        try requireSameNode(fd: directoryFD, parent: parentFD, name: Self.directoryName)
        try requireSameNode(fd: lockFD, parent: directoryFD, name: Self.lockName)
    }

    private func requireSameNode(fd: Int32, parent: Int32, name: String) throws {
        var held = stat(), named = stat()
        guard fstat(fd, &held) == 0,
              fstatat(parent, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
              held.st_dev == named.st_dev, held.st_ino == named.st_ino,
              held.st_mode == named.st_mode, held.st_uid == named.st_uid else {
            throw Self.invalid("The stable command storage or lock was replaced.")
        }
    }

    private func validateParent(_ fd: Int32) throws {
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == expectedUID,
              info.st_mode & S_IFMT == S_IFDIR, info.st_mode & 0o022 == 0 else {
            throw Self.invalid("The storage parent is not a trusted root-owned directory.")
        }
        try validateACL(fd, allowReadOnlyEntries: true)
    }

    private func validateDirectory(_ fd: Int32) throws {
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == expectedUID,
              info.st_mode & S_IFMT == S_IFDIR, info.st_mode & 0o7777 == 0o700 else {
            throw Self.invalid("The command directory must be root-owned with mode 0700.")
        }
        try validateACL(fd, allowReadOnlyEntries: false)
    }

    private func validateFile(_ fd: Int32) throws {
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == expectedUID, info.st_nlink == 1,
              info.st_mode & S_IFMT == S_IFREG, info.st_mode & 0o7777 == 0o600,
              info.st_size >= 0, info.st_size <= Self.maximumBytes else {
            throw Self.invalid("Command evidence must be a private, root-owned regular file with one link.")
        }
        try validateACL(fd, allowReadOnlyEntries: false)
    }

    private func validateACL(_ fd: Int32, allowReadOnlyEntries: Bool) throws {
        errno = 0
        guard let acl = acl_get_fd_np(fd, ACL_TYPE_EXTENDED) else {
            let error = errno
            // Darwin's ACL getter returns nil/ENOENT when a successful fstatx
            // has no FILESEC_ACL property. Confirm that case on the descriptor;
            // a missing pathname or other retrieval error is not an empty ACL.
            if error == ENOENT, try confirmsAbsentACL(fd) { return }
            throw Self.invalid("The storage access-control list could not be inspected.")
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        guard acl_valid(acl) == 0 else { throw Self.invalid("The storage access-control list is invalid.") }
        var entry: acl_entry_t?
        var position = ACL_FIRST_ENTRY.rawValue
        while true {
            errno = 0
            let result = acl_get_entry(acl, position, &entry)
            if result != 0 {
                // Darwin returns EINVAL when a valid ACL has no further entries.
                guard errno == EINVAL else { throw Self.invalid("The access-control list could not be read completely.") }
                return
            }
            guard allowReadOnlyEntries, let entry else {
                throw Self.invalid("Private command evidence cannot have an extended access-control list.")
            }
            var tag = ACL_UNDEFINED_TAG
            var permissions: acl_permset_mask_t = 0
            guard acl_get_tag_type(entry, &tag) == 0,
                  acl_get_permset_mask_np(entry, &permissions) == 0 else {
                throw Self.invalid("An access-control entry could not be inspected.")
            }
            let mutations: [acl_perm_t] = [ACL_WRITE_DATA, ACL_APPEND_DATA,
                ACL_DELETE, ACL_DELETE_CHILD, ACL_WRITE_ATTRIBUTES, ACL_WRITE_EXTATTRIBUTES,
                ACL_WRITE_SECURITY, ACL_CHANGE_OWNER]
            let mutationMask = mutations.reduce(acl_permset_mask_t(0)) { $0 | acl_permset_mask_t($1.rawValue) }
            guard tag == ACL_EXTENDED_DENY ||
                    (tag == ACL_EXTENDED_ALLOW && permissions & mutationMask == 0) else {
                // Inherited and inherit-only entries are not exempt: they can
                // give later descendants authority that POSIX mode bits conceal.
                throw Self.invalid("A storage ancestor grants additional modification access.")
            }
            position = ACL_NEXT_ENTRY.rawValue
        }
    }

    private func confirmsAbsentACL(_ fd: Int32) throws -> Bool {
        guard let security = filesec_init() else { throw Self.invalid("ACL evidence allocation failed.") }
        defer { filesec_free(security) }
        var metadata = stat()
        var present: Int32 = -1
        guard fstatx_np(fd, &metadata, security) == 0,
              filesec_query_property(security, FILESEC_ACL, &present) == 0 else {
            throw Self.invalid("ACL absence could not be verified on the storage descriptor.")
        }
        return present == 0
    }

    private func read(_ name: String) throws -> Data? {
        let fd = openat(directoryFD, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else {
            if errno == ENOENT { return nil }
            throw Self.invalid("The authority record could not be opened safely.")
        }
        defer { _ = Darwin.close(fd) }
        try validateFile(fd)
        var before = stat()
        guard fstat(fd, &before) == 0 else { throw Self.invalid("Evidence metadata is unreadable.") }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw Self.invalid("The authority record could not be read completely.") }
            if count == 0 { break }
            guard data.count + count <= Self.maximumBytes else { throw Self.invalid("Command evidence is oversized.") }
            data.append(contentsOf: buffer.prefix(count))
        }
        var after = stat()
        guard fstat(fd, &after) == 0, before.st_size == after.st_size,
              data.count == Int(after.st_size),
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else {
            throw Self.invalid("The authority record changed while being read.")
        }
        try validateFile(fd)
        try requireSameNode(fd: fd, parent: directoryFD, name: name)
        return data
    }

    private func rejectInterruptedCommit() throws {
        let scanFD = openat(directoryFD, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard scanFD >= 0 else { throw Self.invalid("Command generations could not be inspected.") }
        guard let stream = fdopendir(scanFD) else {
            _ = Darwin.close(scanFD)
            throw Self.invalid("Command generations could not be inspected.")
        }
        var unexpected = false
        errno = 0
        while let entry = readdir(stream) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(cString: $0) }
            }
            if ![".", "..", Self.stateName, Self.lockName].contains(name) { unexpected = true }
            errno = 0
        }
        let readError = errno
        let closeStatus = closedir(stream)
        guard readError == 0, closeStatus == 0, !unexpected else {
            throw Self.invalid("An interrupted or unexpected command generation was preserved.")
        }
    }

    private func encode(_ state: PowerCommandState) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        guard data.count <= Self.maximumBytes else { throw Self.invalid("Command evidence is oversized.") }
        return data
    }

    private func publish(_ data: Data, named name: String) throws {
        let temporary = ".authority-\(UUID().uuidString).tmp"
        let fd = openat(directoryFD, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { throw Self.invalid("A private command generation could not be created.") }
        var open = true
        defer { if open { _ = Darwin.close(fd) } }
        try validateFile(fd)
        try beforeBoundary(.write)
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw Self.invalid("Command evidence could not be written completely.") }
                offset += count
            }
        }
        try synchronize(fd)
        try beforeBoundary(.fileClose)
        open = false
        guard Darwin.close(fd) == 0 else { throw Self.invalid("The command generation could not be closed.") }
        try requireLock()
        try beforeBoundary(.rename)
        guard renameat(directoryFD, temporary, directoryFD, name) == 0 else {
            throw Self.invalid("The command generation could not be published.")
        }
        try synchronize(directoryFD)
    }

    private func synchronize(_ fd: Int32) throws {
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw Self.invalid("Evidence metadata is unreadable during synchronization.") }
        let directory = info.st_mode & S_IFMT == S_IFDIR
        try beforeBoundary(directory ? .directorySync : .fileSync)
        guard fsync(fd) == 0 else {
            throw Self.invalid("Command evidence could not be synchronized durably.")
        }
        try beforeBoundary(directory ? .directoryFullSync : .fileFullSync)
        guard fcntl(fd, F_FULLFSYNC) == 0 else {
            throw Self.invalid("Command evidence could not be synchronized durably.")
        }
    }

    private func closeDescriptors() {
        for fd in [lockFD, directoryFD, parentFD] where fd >= 0 { _ = Darwin.close(fd) }
        lockFD = -1; directoryFD = -1; parentFD = -1
    }

    private static func invalid(_ detail: String) -> PowerCommandStoreError { .unsafeEvidence(detail) }
}
