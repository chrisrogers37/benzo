import Darwin
import Foundation
import MachO

/// Executed only from the hash-checked root-private bootstrap copy. None of
/// these administrative verbs appear in the ordinary sudoers grant.
enum CommandInstaller {
    static let toolName = "com.chrisrogers37.benzo-command"
    static let policyName = "benzo-command"
    static let transactionName = "com.benzo.command-install.json"

    /// A durable allowlist of the exact before/after artifacts of an approved
    /// transaction. It contains no paths or executable input. Repair may finish
    /// a known interrupted publication; unrelated files remain unrecognized.
    struct Transaction: Codable {
        let schema: Int
        let owner: PowerCommandOwner
        let grantEpoch: UUID
        let oldToolDigest: String?
        let oldPolicyDigest: String?
        let newToolDigest: String?
        let newPolicyDigest: String?

        init(owner: PowerCommandOwner, grantEpoch: UUID, oldTool: Data?, oldPolicy: Data?, newTool: Data?, newPolicy: Data?) {
            schema = 1; self.owner = owner; self.grantEpoch = grantEpoch
            oldToolDigest = oldTool.map(CommandToolIdentity.digest)
            oldPolicyDigest = oldPolicy.map(CommandToolIdentity.digest)
            newToolDigest = newTool.map(CommandToolIdentity.digest)
            newPolicyDigest = newPolicy.map(CommandToolIdentity.digest)
        }

        func admits(tool: Data?, policy: Data?, owner: PowerCommandOwner, epoch: UUID) -> Bool {
            let digests = [oldToolDigest, oldPolicyDigest, newToolDigest, newPolicyDigest].compactMap { $0 }
            guard schema == 1, self.owner == owner, grantEpoch == epoch,
                  epoch != PowerCommandWire.zeroUUID,
                  (newToolDigest == nil) == (newPolicyDigest == nil),
                  digests.allSatisfy(CommandToolIdentity.validDigest) else { return false }
            if let tool {
                guard [oldToolDigest, newToolDigest].contains(CommandToolIdentity.digest(tool)) else { return false }
            } else if oldToolDigest != nil && newToolDigest != nil { return false }
            if let policy {
                guard [oldPolicyDigest, newPolicyDigest].contains(CommandToolIdentity.digest(policy)) else { return false }
            }
            // A missing policy is valid during rollback's revoke-first step.
            return true
        }
    }

    static func policy(owner: PowerCommandOwner, digest: String) throws -> Data {
        try owner.validate()
        guard owner.uid >= 501, owner.uid < UInt32.max,
              CommandToolIdentity.validDigest(digest) else {
            throw PowerCommandError.invalid("The command policy identity is invalid.")
        }
        let path = CommandToolIdentity.installedPath
        let commands = PowerCommandVerb.allCases.map { "sha256:\(digest) \(path) \($0.rawValue)" }.joined(separator: ", ")
        return Data(("# Benzo account command policy v1\n" +
            "Defaults!\(path) stay_setuid,env_reset,!setenv\n" +
            "#\(owner.uid) ALL=(root) NOPASSWD: NOSETENV: \(commands)\n").utf8)
    }

#if !BENZO_STORAGE_TESTS
    static func perform(arguments: [String]) throws {
        guard geteuid() == 0, arguments.count == 4,
              ["install-v1", "repair-v1", "remove-v1"].contains(arguments[0]),
              let uid = UInt32(arguments[1]), String(uid) == arguments[1],
              let uuid = UUID(uuidString: arguments[2]), uuid.uuidString == arguments[2],
              CommandToolIdentity.validDigest(arguments[3]) else {
            throw PowerCommandError.invalid("The administrator setup request is invalid.")
        }
        let owner = PowerCommandOwner(uid: uid, generatedUID: uuid)
        guard try CommandToolIdentity.localOwner(uid: uid) == owner else {
            throw PowerCommandError.invalid("The approved local account changed before setup. Start setup again.")
        }
        guard setgroups(0, nil) == 0, setgid(0) == 0, setuid(0) == 0 else {
            throw PowerCommandError.invalid("Administrator setup credentials are unavailable.")
        }
        umask(0o077)
        let executable = try checkedBootstrapExecutable()
        let bytes = try CommandToolIdentity.executableBytes(at: executable)
        guard CommandToolIdentity.digest(bytes) == arguments[3] else {
            throw PowerCommandError.invalid("The administrator-approved command bytes no longer match.")
        }
        guard try !pathExists(CommandToolIdentity.legacyStatePath) else {
            throw PowerCommandError.invalid("An earlier Benzo helper has authority or recovery records. Resolve and retire that helper with an administrator before this setup; its records were retained.")
        }
        try checkPolicy()
        let tools = try InstallDirectory(path: "/Library/PrivilegedHelperTools", createLast: true)
        let policies = try InstallDirectory(path: "/private/etc/sudoers.d", createLast: false)
        let transactions = try InstallDirectory(path: "/private/var/db", createLast: false)
        let exists = try pathExists(PowerCommandStore.path)
        if !exists {
            guard arguments[0] == "install-v1",
                  try tools.read(toolName, mode: 0o555, limit: CommandToolIdentity.maximumExecutableBytes) == nil,
                  try policies.read(policyName, mode: 0o440, limit: 16_384) == nil,
                  try transactions.read(transactionName, mode: 0o600, limit: 4_096) == nil else {
                throw PowerCommandError.invalid("Existing Benzo installation evidence is incomplete. Administrator recovery is required.")
            }
        }
        let store = try exists ? PowerCommandStore() :
            PowerCommandStore.installInitialState(PowerCommandState.initial(owner: owner))
        defer { withExtendedLifetime(store) {} }
        let state = try store.load()
        guard state.owner == owner, state.pending == nil else {
            throw PowerCommandError.invalid("Resolve this account's retained command receipt before changing installation. Ownership was not transferred.")
        }
        // Capture rollback generations only after acquiring the same stable
        // lock as normal commands and every other installer invocation.
        let existingTool = try tools.read(toolName, mode: 0o555, limit: CommandToolIdentity.maximumExecutableBytes)
        let existingPolicy = try policies.read(policyName, mode: 0o440, limit: 16_384)
        let transactionBytes = try transactions.read(transactionName, mode: 0o600, limit: 4_096)
        if let transactionBytes {
            guard let transaction = try? JSONDecoder().decode(Transaction.self, from: transactionBytes),
                  transaction.admits(tool: existingTool, policy: existingPolicy, owner: owner, epoch: state.grantEpoch) else {
                throw PowerCommandError.invalid("The interrupted setup does not match its approved account and file generations. Administrator recovery is required.")
            }
        } else if let existingTool, let existingPolicy {
            guard existingPolicy == (try policy(owner: owner, digest: CommandToolIdentity.digest(existingTool))) else {
                throw PowerCommandError.invalid("The existing command policy is not Benzo's exact recognized policy. It was not changed.")
            }
        } else if existingTool != nil || existingPolicy != nil {
            throw PowerCommandError.invalid("The installed command and policy do not agree. Administrator recovery is required.")
        }
        guard try CommandToolIdentity.localOwner(uid: owner.uid) == owner else {
            throw PowerCommandError.invalid("The approved account changed during setup.")
        }
        if arguments[0] == "remove-v1" {
            try remove(tools: tools, policies: policies, transactions: transactions, owner: owner,
                       epoch: state.grantEpoch, oldTool: existingTool, oldPolicy: existingPolicy)
        } else {
            try install(tools: tools, policies: policies, transactions: transactions, owner: owner,
                        epoch: state.grantEpoch, bytes: bytes, digest: arguments[3],
                        oldTool: existingTool, oldPolicy: existingPolicy)
        }
        // The grant, epoch, watermark and receipt history are never removed or
        // recreated by replacement/removal. App readiness uses a separate,
        // ordinary nonmutating sudo -n version exchange after this process exits.
    }

    private static func install(tools: InstallDirectory, policies: InstallDirectory, transactions: InstallDirectory,
                                owner: PowerCommandOwner, epoch: UUID, bytes: Data, digest: String,
                                oldTool: Data?, oldPolicy: Data?) throws {
        let candidate = try policy(owner: owner, digest: digest)
        let candidateName = ".benzo-candidate-\(UUID().uuidString)"
        try policies.publish(candidate, name: candidateName, mode: 0o440)
        defer { try? policies.remove(candidateName) }
        try checkPolicy(at: policies.path + "/" + candidateName)
        let transaction = Transaction(owner: owner, grantEpoch: epoch, oldTool: oldTool,
                                      oldPolicy: oldPolicy, newTool: bytes, newPolicy: candidate)
        try transactions.publish(JSONEncoder().encode(transaction), name: transactionName, mode: 0o600)
        do {
            // Binary first means an old hash-pinned rule temporarily denies
            // execution. The root store lock excludes already admitted writes.
            try tools.publish(bytes, name: toolName, mode: 0o555)
            try policies.publish(candidate, name: policyName, mode: 0o440)
            try checkPolicy() // fragment-only validation is insufficient
            try transactions.remove(transactionName)
        } catch {
            // A failed final directory sync may have already unlinked the
            // marker. Re-establish it before restoring partial generations.
            try transactions.publish(JSONEncoder().encode(transaction), name: transactionName, mode: 0o600)
            try rollback(tools: tools, policies: policies, oldTool: oldTool, oldPolicy: oldPolicy)
            // If rollback restores an already partial older transaction,
            // keep this marker so another explicit Repair can recognize it.
            if try artifactsAgree(tool: oldTool, policy: oldPolicy, owner: owner) {
                try transactions.remove(transactionName)
            }
            throw error
        }
    }

    private static func remove(tools: InstallDirectory, policies: InstallDirectory, transactions: InstallDirectory,
                               owner: PowerCommandOwner, epoch: UUID, oldTool: Data?, oldPolicy: Data?) throws {
        let transaction = Transaction(owner: owner, grantEpoch: epoch, oldTool: oldTool,
                                      oldPolicy: oldPolicy, newTool: nil, newPolicy: nil)
        try transactions.publish(JSONEncoder().encode(transaction), name: transactionName, mode: 0o600)
        do {
            // Revocation precedes executable removal; no other sudoers file is
            // changed and the stable root authority directory remains intact.
            try policies.remove(policyName)
            try checkPolicy()
            try tools.remove(toolName)
            try transactions.remove(transactionName)
        } catch {
            try transactions.publish(JSONEncoder().encode(transaction), name: transactionName, mode: 0o600)
            try rollback(tools: tools, policies: policies, oldTool: oldTool, oldPolicy: oldPolicy)
            if try artifactsAgree(tool: oldTool, policy: oldPolicy, owner: owner) {
                try transactions.remove(transactionName)
            }
            throw error
        }
    }

    private static func artifactsAgree(tool: Data?, policy: Data?, owner: PowerCommandOwner) throws -> Bool {
        if tool == nil && policy == nil { return true }
        guard let tool, let policy else { return false }
        return policy == (try Self.policy(owner: owner, digest: CommandToolIdentity.digest(tool)))
    }

    private static func rollback(tools: InstallDirectory, policies: InstallDirectory,
                                 oldTool: Data?, oldPolicy: Data?) throws {
        do {
            try policies.remove(policyName)
            if let oldTool { try tools.publish(oldTool, name: toolName, mode: 0o555) }
            else { try tools.remove(toolName) }
            if let oldPolicy { try policies.publish(oldPolicy, name: policyName, mode: 0o440) }
            try checkPolicy()
        } catch {
            // Best effort revocation leaves no broad fallback permission. A
            // failed restore is reported as unresolved, never successful setup.
            try? policies.remove(policyName)
            throw PowerCommandError.invalid("Setup failed and its previous installation could not be restored completely. Access remains unavailable; administrator recovery is required. Account and recovery records were retained.")
        }
    }

    private static func checkPolicy(at path: String? = nil) throws {
        let args = path.map { ["-c", "-f", $0] } ?? ["-c"]
        let result = CommandRuntime.run(executable: "/usr/sbin/visudo", arguments: args, timeout: 10, maximumBytes: 65_536)
        guard result.succeeded else {
            throw PowerCommandError.invalid("The system administrator policy could not be validated. Benzo did not accept this installation.")
        }
    }

    private static func checkedBootstrapExecutable() throws -> String {
        var size: UInt32 = 4_096
        var buffer = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&buffer, &size) == 0 else {
            throw PowerCommandError.invalid("The approved installer path is unavailable.")
        }
        let path = String(cString: buffer)
        let parent = (path as NSString).deletingLastPathComponent
        guard (path as NSString).lastPathComponent == "tool",
              (parent as NSString).deletingLastPathComponent == "/private/var/tmp",
              (parent as NSString).lastPathComponent.hasPrefix("com.benzo.command.") else {
            throw PowerCommandError.invalid("Setup must run from its approved private staging directory.")
        }
        let directory = open(parent, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw PowerCommandError.invalid("The installer staging directory is unsafe.") }
        defer { _ = Darwin.close(directory) }
        var metadata = stat()
        guard fstat(directory, &metadata) == 0, metadata.st_uid == 0,
              metadata.st_mode & 0o7777 == 0o700 else {
            throw PowerCommandError.invalid("The installer staging directory is not private to root.")
        }
        try InstallDirectory.checkACL(directory, privateOnly: true)
        let file = openat(directory, "tool", O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard file >= 0 else { throw PowerCommandError.invalid("The approved staged command is unavailable.") }
        defer { _ = Darwin.close(file) }
        guard fstat(file, &metadata) == 0, metadata.st_uid == 0, metadata.st_nlink == 1,
              metadata.st_mode & S_IFMT == S_IFREG, metadata.st_mode & 0o7777 == 0o700 else {
            throw PowerCommandError.invalid("The approved staged command is not a private root-owned file.")
        }
        try InstallDirectory.checkACL(file, privateOnly: true)
        return path
    }

    private static func pathExists(_ path: String) throws -> Bool {
        var metadata = stat()
        if lstat(path, &metadata) == 0 { return true }
        guard errno == ENOENT else { throw PowerCommandError.invalid("Existing installation evidence could not be inspected.") }
        return false
    }
#endif
}

/// Descriptor-relative publication under root-protected, non-symlink ancestry.
/// Existing entries must already have the exact modes written by this installer.
#if !BENZO_STORAGE_TESTS
private final class InstallDirectory {
    let path: String
    private var fd: Int32

    init(path: String, createLast: Bool) throws {
        self.path = path
        fd = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw Self.failure("The root filesystem is inaccessible.") }
        do {
            try Self.checkDirectory(fd)
            let components = path.split(separator: "/").map(String.init)
            for (index, component) in components.enumerated() {
                var next = openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                var created = false
                if next < 0, errno == ENOENT, createLast, index == components.count - 1 {
                    guard mkdirat(fd, component, 0o755) == 0 else { throw Self.failure("The tool directory could not be created.") }
                    created = true
                    guard fsync(fd) == 0 else { throw Self.failure("The new tool directory could not be synchronized.") }
                    next = openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                }
                guard next >= 0 else { throw Self.failure("An installation directory is missing or unsafe.") }
                do {
                    try Self.checkDirectory(next)
                    if created {
                        // Setup's 0077 umask keeps a new directory private
                        // until its root ownership/ACL have been verified.
                        guard fchmod(next, 0o755) == 0, fsync(next) == 0 else {
                            throw Self.failure("The new tool directory could not be secured durably.")
                        }
                    }
                }
                catch { _ = Darwin.close(next); throw error }
                _ = Darwin.close(fd); fd = next
            }
        } catch { _ = Darwin.close(fd); fd = -1; throw error }
    }

    deinit { if fd >= 0 { _ = Darwin.close(fd) } }

    func read(_ name: String, mode: mode_t, limit: Int) throws -> Data? {
        let file = openat(fd, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        if file < 0, errno == ENOENT { return nil }
        guard file >= 0 else { throw Self.failure("An existing installed file could not be opened safely.") }
        defer { _ = Darwin.close(file) }
        var info = stat()
        guard fstat(file, &info) == 0, info.st_uid == 0, info.st_gid == 0,
              info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1,
              info.st_mode & 0o7777 == mode, info.st_size >= 0, info.st_size <= limit else {
            throw Self.failure("An existing installed file has unrecognized ownership, permissions or size.")
        }
        try Self.checkACL(file, privateOnly: true)
        var data = Data(), buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = Darwin.read(file, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            guard count >= 0, data.count + max(0, count) <= limit else { throw Self.failure("An installed file could not be read completely.") }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        guard data.count == Int(info.st_size) else { throw Self.failure("An installed file changed while it was inspected.") }
        return data
    }

    func publish(_ data: Data, name: String, mode: mode_t) throws {
        try Self.checkDirectory(fd)
        let temporary = ".benzo-write-\(UUID().uuidString)"
        let file = openat(fd, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard file >= 0 else { throw Self.failure("A private installation generation could not be created.") }
        var closed = false
        defer {
            if !closed { _ = Darwin.close(file) }
            _ = unlinkat(fd, temporary, 0)
        }
        try Self.checkACL(file, privateOnly: true)
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(file, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw Self.failure("The installation generation could not be written completely.") }
                offset += count
            }
        }
        guard fchown(file, 0, 0) == 0, fchmod(file, mode) == 0,
              fsync(file) == 0, fcntl(file, F_FULLFSYNC) == 0 else {
            throw Self.failure("The installation generation could not be secured and synchronized.")
        }
        closed = true
        guard Darwin.close(file) == 0,
              renameat(fd, temporary, fd, name) == 0, fsync(fd) == 0 else {
            throw Self.failure("The installation generation could not be published durably.")
        }
    }

    func remove(_ name: String) throws {
        try Self.checkDirectory(fd)
        guard unlinkat(fd, name, 0) == 0 || errno == ENOENT else { throw Self.failure("An owned installation file could not be removed.") }
        guard fsync(fd) == 0 else { throw Self.failure("Installation removal could not be synchronized.") }
    }

    private static func checkDirectory(_ fd: Int32) throws {
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == 0,
              info.st_mode & S_IFMT == S_IFDIR, info.st_mode & 0o022 == 0 else {
            throw failure("An installation ancestor is not protected by root.")
        }
        try checkACL(fd, privateOnly: false)
    }

    static func checkACL(_ fd: Int32, privateOnly: Bool) throws {
        errno = 0
        guard let acl = acl_get_fd_np(fd, ACL_TYPE_EXTENDED) else {
            guard errno == ENOENT, let security = filesec_init() else { throw failure("Installation ACL evidence is unavailable.") }
            defer { filesec_free(security) }
            var info = stat(), present: Int32 = -1
            guard fstatx_np(fd, &info, security) == 0,
                  filesec_query_property(security, FILESEC_ACL, &present) == 0, present == 0 else {
                throw failure("Installation ACL absence could not be verified.")
            }
            return
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        guard acl_valid(acl) == 0 else { throw failure("An installation ACL is invalid.") }
        var entry: acl_entry_t?
        var position = ACL_FIRST_ENTRY.rawValue
        while true {
            errno = 0
            if acl_get_entry(acl, position, &entry) != 0 {
                guard errno == EINVAL else { throw failure("An installation ACL could not be read.") }
                return
            }
            guard !privateOnly, let entry else { throw failure("An installed private file has an unexpected ACL.") }
            var tag = ACL_UNDEFINED_TAG
            var permissions: acl_permset_mask_t = 0
            guard acl_get_tag_type(entry, &tag) == 0, acl_get_permset_mask_np(entry, &permissions) == 0 else {
                throw failure("An installation ACL entry is unreadable.")
            }
            let changes: [acl_perm_t] = [ACL_WRITE_DATA, ACL_APPEND_DATA, ACL_DELETE, ACL_DELETE_CHILD,
                ACL_WRITE_ATTRIBUTES, ACL_WRITE_EXTATTRIBUTES, ACL_WRITE_SECURITY, ACL_CHANGE_OWNER]
            let mask = changes.reduce(acl_permset_mask_t(0)) { $0 | acl_permset_mask_t($1.rawValue) }
            guard tag == ACL_EXTENDED_DENY || (tag == ACL_EXTENDED_ALLOW && permissions & mask == 0) else {
                throw failure("An installation ancestor grants additional modification access.")
            }
            position = ACL_NEXT_ENTRY.rawValue
        }
    }

    private static func failure(_ message: String) -> PowerCommandError { .invalid(message) }
}
#endif
