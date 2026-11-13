import Foundation

enum HelperIdentityError: LocalizedError {
    case invalidSigningIdentity
    case invalidLocalAccount

    var errorDescription: String? {
        switch self {
        case .invalidSigningIdentity:
            return "Benzo needs a valid Developer ID signed build before its helper can be used."
        case .invalidLocalAccount:
            return "Benzo could not verify this local Mac account. Power-setting access remains unavailable."
        }
    }
}

/// Pure requirement construction, shared with the unhosted tests. This does not
/// inspect the host's signing identity, accounts, or authorization state.
enum HelperCodeRequirement {
    static let appIdentifier = "com.benzo.app"
    static let helperIdentifier = "com.benzo.helper"

    /// The production caller obtains the team from its own verified signature.
    /// Closed identifiers and an ASCII Team ID prevent requirement injection.
    static func requirement(for identifier: String, teamIdentifier: String) throws -> String {
        guard [appIdentifier, helperIdentifier].contains(identifier),
              teamIdentifier.utf8.count == 10,
              teamIdentifier.utf8.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) }) else {
            throw HelperIdentityError.invalidSigningIdentity
        }
        // The signed marker excludes older same-identifier releases. Info.plist
        // supports app-defined metadata; invented entitlements can prevent launch.
        // The tool embeds its plist in __TEXT,__info_plist before code signing.
        let role = identifier == appIdentifier ? "client-v1" : "service-v1"
        return "anchor apple generic" +
            " and certificate 1[field.1.2.840.113635.100.6.2.6] exists" +
            " and certificate leaf[field.1.2.840.113635.100.6.1.13] exists" +
            " and certificate leaf[subject.OU] = \"\(teamIdentifier)\"" +
            " and identifier \"\(identifier)\"" +
            " and info[BenzoHelperRole] = \"\(role)\"" +
            " and ! entitlement[\"com.apple.security.get-task-allow\"] exists" +
            " and ! entitlement[\"com.apple.security.cs.disable-library-validation\"] exists" +
            " and ! entitlement[\"com.apple.security.cs.allow-dyld-environment-variables\"] exists"
    }
}
