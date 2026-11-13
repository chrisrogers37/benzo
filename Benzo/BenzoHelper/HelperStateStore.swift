import Darwin
import Foundation

enum HelperStateStoreError: LocalizedError {
    case unsafeEvidence(String)

    var errorDescription: String? {
        switch self {
        case .unsafeEvidence(let detail):
            return "Benzo's helper evidence needs administrator recovery. " + detail
        }
    }
}

enum HelperStoreBoundary: CaseIterable {
    case write, fileSync, fileFullSync, fileClose, rename
    case directorySync, directoryFullSync, pendingRemove
}

/// Root-only, fixed-path storage. This contains the account grant and execution
/// admission evidence, never user-provided paths or the GUI's original settings.
/// Creation and every access are descriptor-relative; the stable lock remains
/// held for this object's lifetime. Only daemon composition constructs this type.
final class HelperStateStore: HelperAuthorityStoring {
    static let path = "/private/var/db/com.benzo.helper"
    private static let directoryName = "com.benzo.helper"
    private static let stateName = "authority.json"
    private static let lockName = "authority.lock"
    private static let pendingName = "commit-pending.json"
    private static let maximumBytes = 65_536

    private var parentFD: Int32 = -1
    private var directoryFD: Int32 = -1
    private var lockFD: Int32 = -1
    private let expectedUID: UInt32
    private let beforeBoundary: (HelperStoreBoundary) throws -> Void

    /// A valid explicit null state means initialization finished but no account
    /// has enrolled. An absent file in an existing directory never means that.
    private struct Envelope: Codable {
        let schema: Int
        let state: HelperAuthorityState?
        private enum CodingKeys: String, CodingKey { case schema, state }

        init(state: HelperAuthorityState?) { schema = 1; self.state = state }
        init(from decoder: Decoder) throws {
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            schema = try fields.decode(Int.self, forKey: .schema)
            state = try fields.decode(HelperAuthorityState?.self, forKey: .state)
        }
        func encode(to encoder: Encoder) throws {
            var fields = encoder.container(keyedBy: CodingKeys.self)
            try fields.encode(schema, forKey: .schema)
            try fields.encode(state, forKey: .state)
        }
    }

    init() throws {
        expectedUID = 0
        beforeBoundary = { _ in }
        guard geteuid() == 0, getuid() == 0 else {
            throw Self.invalid("The store can only be opened by the system helper.")
        }
        do {
            let created = try openDirectory()
            try acquireLock(creating: created)
            if created {
                // Publish before the listener can accept any request. A crash in
                // initialization leaves evidence requiring inspection, not reset.
                try publish(encode(Envelope(state: nil)), named: Self.stateName)
            }
            _ = try load()
        } catch {
            closeDescriptors()
            throw error
        }
    }

#if BENZO_STORAGE_TESTS
    /// Only the unhosted test build includes this entry point. It creates and
    /// owns a private fixture beneath a caller-owned temporary directory. The
    /// production binary has no configurable path, UID, or durability hook.
    init(testingParentDirectory: URL,
         beforeBoundary: @escaping (HelperStoreBoundary) throws -> Void = { _ in }) throws {
        expectedUID = getuid()
        self.beforeBoundary = beforeBoundary
        guard expectedUID != 0, geteuid() == expectedUID,
              testingParentDirectory.isFileURL else {
            throw Self.invalid("Storage fixtures must run as an unprivileged account.")
        }
        do {
            parentFD = Darwin.open(testingParentDirectory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard parentFD >= 0 else { throw Self.invalid("The private fixture parent is inaccessible.") }
            try validateParent(parentFD)
            let created = mkdirat(parentFD, Self.directoryName, mode_t(0o700)) == 0
            guard created || errno == EEXIST else { throw Self.invalid("The fixture could not be created.") }
            directoryFD = openat(parentFD, Self.directoryName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard directoryFD >= 0 else { throw Self.invalid("The private fixture directory is unsafe.") }
            try validateDirectory(directoryFD)
            if created { try synchronize(parentFD) }
            try acquireLock(creating: created)
            if created { try publish(encode(Envelope(state: nil)), named: Self.stateName) }
            _ = try load()
        } catch {
            closeDescriptors()
            throw error
        }
    }
#endif

    deinit { closeDescriptors() }

    func load() throws -> HelperAuthorityState? {
        try requireLock()
        try rejectInterruptedCommit()
        guard let bytes = try read(Self.stateName) else {
            throw Self.invalid("The established authority record is missing.")
        }
        let envelope: Envelope
        do { envelope = try JSONDecoder().decode(Envelope.self, from: bytes) }
        catch { throw Self.invalid("The authority record is malformed or unsupported.") }
        guard envelope.schema == 1 else { throw Self.invalid("The authority record schema is unsupported.") }
        try envelope.state?.validate()
        return envelope.state
    }

    func commit(_ state: HelperAuthorityState) throws {
        try state.validate()
        let old = try load()
        if let old {
            guard state.owner == old.owner else {
                throw Self.invalid("The enrolled account cannot be replaced.")
            }
            if state.revision == old.revision {
                guard state == old || (old.lastExecution?.isIncomplete == true &&
                    state.lastExecution?.request == old.lastExecution?.request &&
                    state.lastExecution?.isIncomplete == false &&
                    state.priorUncertainExecution == old.priorUncertainExecution) else {
                    throw Self.invalid("Completion cannot replace an admitted request or existing receipt.")
                }
            } else {
                guard old.revision < UInt64.max, state.revision == old.revision + 1,
                      state.lastExecution?.isIncomplete == true else {
                    throw Self.invalid("Admission revisions must advance exactly once before execution.")
                }
                if old.lastExecution?.isIncomplete == true {
                    guard old.priorUncertainExecution == nil,
                          state.priorUncertainExecution == old.lastExecution else {
                        throw Self.invalid("Previous execution uncertainty must be preserved.")
                    }
                } else if state.priorUncertainExecution != old.priorUncertainExecution {
                    throw Self.invalid("Prior execution evidence cannot be replaced.")
                }
            }
        } else if state.revision != 0 || state.lastExecution != nil || state.priorUncertainExecution != nil {
            throw Self.invalid("Enrollment cannot fabricate prior execution evidence.")
        }
        // Preserve the old generation durably before a completed/new generation
        // can become visible. If publication fails after rename, a restart must
        // not mistake that visible generation for a successfully committed one.
        try publish(encode(Envelope(state: old)), named: Self.pendingName)
        try publish(encode(Envelope(state: state)), named: Self.stateName)
        try beforeBoundary(.pendingRemove)
        guard unlinkat(directoryFD, Self.pendingName, 0) == 0 else {
            throw Self.invalid("The committed generation could not be finalized.")
        }
        // State was fully durable before unlink. A surviving marker fences a
        // restart; absence cannot hide a failure publishing the state itself.
        try synchronize(directoryFD)
    }

    private func openDirectory() throws -> Bool {
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
            let created = mkdirat(ancestor, Self.directoryName, mode_t(0o700)) == 0
            guard created || errno == EEXIST else { throw Self.invalid("Private helper storage could not be created.") }
            let opened = openat(ancestor, Self.directoryName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard opened >= 0 else { throw Self.invalid("The helper storage path is not a safe directory.") }
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
        guard opened >= 0 else { throw Self.invalid("The established helper lock is missing or unsafe.") }
        do {
            try validateFile(opened)
            guard flock(opened, LOCK_EX | LOCK_NB) == 0 else {
                throw Self.invalid("Another helper instance holds admission.")
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
            throw Self.invalid("The helper has not acquired exclusive admission.")
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
            throw Self.invalid("The stable helper storage or lock was replaced.")
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
            throw Self.invalid("The helper directory must be root-owned with mode 0700.")
        }
        try validateACL(fd, allowReadOnlyEntries: false)
    }

    private func validateFile(_ fd: Int32) throws {
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == expectedUID, info.st_nlink == 1,
              info.st_mode & S_IFMT == S_IFREG, info.st_mode & 0o7777 == 0o600,
              info.st_size >= 0, info.st_size <= Self.maximumBytes else {
            throw Self.invalid("Helper evidence must be a private, root-owned regular file with one link.")
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
                throw Self.invalid("Private helper evidence cannot have an extended access-control list.")
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
            guard data.count + count <= Self.maximumBytes else { throw Self.invalid("Helper evidence is oversized.") }
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
        guard scanFD >= 0 else { throw Self.invalid("Helper generations could not be inspected.") }
        guard let stream = fdopendir(scanFD) else {
            _ = Darwin.close(scanFD)
            throw Self.invalid("Helper generations could not be inspected.")
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
            throw Self.invalid("An interrupted or unexpected helper generation was preserved.")
        }
    }

    private func encode(_ envelope: Envelope) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(envelope)
        guard data.count <= Self.maximumBytes else { throw Self.invalid("Helper evidence is oversized.") }
        return data
    }

    private func publish(_ data: Data, named name: String) throws {
        let temporary = ".authority-\(UUID().uuidString).tmp"
        let fd = openat(directoryFD, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { throw Self.invalid("A private helper generation could not be created.") }
        var open = true
        defer { if open { _ = Darwin.close(fd) } }
        try validateFile(fd)
        try beforeBoundary(.write)
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw Self.invalid("Helper evidence could not be written completely.") }
                offset += count
            }
        }
        try synchronize(fd)
        try beforeBoundary(.fileClose)
        open = false
        guard Darwin.close(fd) == 0 else { throw Self.invalid("The helper generation could not be closed.") }
        try requireLock()
        try beforeBoundary(.rename)
        guard renameat(directoryFD, temporary, directoryFD, name) == 0 else {
            throw Self.invalid("The helper generation could not be published.")
        }
        try synchronize(directoryFD)
    }

    private func synchronize(_ fd: Int32) throws {
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw Self.invalid("Evidence metadata is unreadable during synchronization.") }
        let directory = info.st_mode & S_IFMT == S_IFDIR
        try beforeBoundary(directory ? .directorySync : .fileSync)
        guard fsync(fd) == 0 else {
            throw Self.invalid("Helper evidence could not be synchronized durably.")
        }
        try beforeBoundary(directory ? .directoryFullSync : .fileFullSync)
        guard fcntl(fd, F_FULLFSYNC) == 0 else {
            throw Self.invalid("Helper evidence could not be synchronized durably.")
        }
    }

    private func closeDescriptors() {
        for fd in [lockFD, directoryFD, parentFD] where fd >= 0 { _ = Darwin.close(fd) }
        lockFD = -1; directoryFD = -1; parentFD = -1
    }

    private static func invalid(_ detail: String) -> HelperStateStoreError { .unsafeEvidence(detail) }
}
