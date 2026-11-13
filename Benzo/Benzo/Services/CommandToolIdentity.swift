import CryptoKit
import Darwin
import Foundation
import OpenDirectory

/// This transport grants an account, not a signing identity or one app process.
/// Only the app's pre-approval identity and the tool's kernel real UID select an
/// account. Environment variables and request JSON never select the beneficiary.
enum CommandToolIdentity {
    static let installedPath = "/Library/PrivilegedHelperTools/com.chrisrogers37.benzo-command"
    static let policyPath = "/private/etc/sudoers.d/benzo-command"
    static let legacyStatePath = "/private/var/db/com.benzo.helper"
    static let maximumExecutableBytes = 64 * 1_024 * 1_024

#if !BENZO_STORAGE_TESTS
    static func currentOwner() throws -> PowerCommandOwner {
        guard getuid() == geteuid() else {
            throw PowerCommandError.invalid("Open Benzo normally from the account that will use it.")
        }
        return try localOwner(uid: getuid())
    }

    static func localOwner(uid: UInt32) throws -> PowerCommandOwner {
        let record = try localRecord(uid: uid)
        let identifiers = try record.values(forAttribute: kODAttributeTypeUniqueID)
        let generated = try record.values(forAttribute: kODAttributeTypeGUID)
        guard identifiers.count == 1, identifiers[0] as? String == String(uid),
              generated.count == 1, let text = generated[0] as? String,
              text.utf8.count == 36, let uuid = UUID(uuidString: text),
              uuid != PowerCommandWire.zeroUUID else {
            throw PowerCommandError.invalid("The local account identity could not be verified.")
        }
        return PowerCommandOwner(uid: uid, generatedUID: uuid)
    }

    static func localAccountName(uid: UInt32) throws -> String {
        guard let name = try localRecord(uid: uid).recordName, !name.isEmpty, name.utf8.count <= 256,
              name.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw PowerCommandError.invalid("The local account name could not be displayed safely.")
        }
        return name
    }

    private static func localRecord(uid: UInt32) throws -> ODRecord {
        guard uid >= 501, uid < UInt32.max else {
            throw PowerCommandError.invalid("Benzo setup requires a local user account.")
        }
        let node = try ODNode(session: ODSession.default(), type: ODNodeType(kODNodeTypeLocalNodes))
        let query = try ODQuery(node: node, forRecordTypes: kODRecordTypeUsers,
            attribute: kODAttributeTypeUniqueID, matchType: ODMatchType(kODMatchEqualTo),
            queryValues: String(uid),
            returnAttributes: [kODAttributeTypeUniqueID, kODAttributeTypeGUID, kODAttributeTypeRecordName],
            maximumResults: 2)
        guard let records = try query.resultsAllowingPartial(false) as? [ODRecord], records.count == 1 else {
            throw PowerCommandError.invalid("Benzo requires one uniquely identified local account.")
        }
        return records[0]
    }
#endif

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Read one regular inode without following a last-component symlink. The
    /// bootstrap hashes its private copy again; a source race cannot approve
    /// different installed bytes.
#if !BENZO_STORAGE_TESTS
    static func executableBytes(at path: String) throws -> Data {
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw PowerCommandError.invalid("Benzo's bundled command tool is unavailable.") }
        defer { _ = Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size > 0, info.st_size <= maximumExecutableBytes else {
            throw PowerCommandError.invalid("Benzo's bundled command tool is invalid.")
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            guard count >= 0, data.count + max(0, count) <= maximumExecutableBytes else {
                throw PowerCommandError.invalid("Benzo's command tool could not be read completely.")
            }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        guard data.count == Int(info.st_size) else {
            throw PowerCommandError.invalid("Benzo's command tool changed while preparing setup. Try again.")
        }
        return data
    }
#endif
}
