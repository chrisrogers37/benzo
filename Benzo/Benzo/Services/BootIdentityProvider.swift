import Foundation
import Darwin

/// Live identity lookups; application composition injects these into the coordinator.
struct BootIdentityProvider {
    static func bootID() throws -> String {
        var bytes = [CChar](repeating: 0, count: 128)
        var count = bytes.count
        guard sysctlbyname("kern.bootsessionuuid", &bytes, &count, nil, 0) == 0,
              count > 1, count <= bytes.count, bytes[count - 1] == 0 else {
            throw RecoveryEvidenceError.invalid("The current boot identity could not be verified. Settings remain protected.")
        }
        let content = bytes.prefix(count - 1).map { UInt8(bitPattern: $0) }
        guard content.count == 36, let value = String(bytes: content, encoding: .utf8),
              let uuid = UUID(uuidString: value) else {
            throw RecoveryEvidenceError.invalid("The current boot identity is invalid. Settings remain protected.")
        }
        return uuid.uuidString
    }

    static func hostID() throws -> String {
        var value: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        var timeout = timespec(tv_sec: 2, tv_nsec: 0)
        guard gethostuuid(&value, &timeout) == 0 else {
            throw RecoveryEvidenceError.invalid("This Mac's identity could not be verified. Recovery evidence was preserved.")
        }
        let uuid = UUID(uuid: value)
        guard uuid.uuidString != "00000000-0000-0000-0000-000000000000" else {
            throw RecoveryEvidenceError.invalid("This Mac's identity is unavailable. Recovery evidence was preserved.")
        }
        return uuid.uuidString
    }
}
