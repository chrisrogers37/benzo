import Foundation
import OpenDirectory
import Security

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

/// Shared by the app and daemon. No ad-hoc or unsigned development exception is
/// accepted by the privileged transport; tests use the pure requirement builder.
enum HelperIdentity {
    static let appIdentifier = "com.benzo.app"
    static let helperIdentifier = "com.benzo.helper"

    /// Cache this at helper startup. Validating the dynamic code against the
    /// extracted hash prevents an old running helper from reporting a new binary
    /// that has replaced its on-disk path during an app update.
    static func ownCodeHash() throws -> String {
        _ = try requirement(for: helperIdentifier)
        var code: SecCode?
        var staticCode: SecStaticCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
            throw HelperIdentityError.invalidSigningIdentity
        }
        let hash = try codeHash(staticCode)
        var hashRequirement: SecRequirement?
        guard SecRequirementCreateWithString("cdhash H\"\(hash)\"" as CFString, [], &hashRequirement) == errSecSuccess,
              let hashRequirement,
              SecCodeCheckValidity(code, [], hashRequirement) == errSecSuccess else {
            throw HelperIdentityError.invalidSigningIdentity
        }
        return hash
    }

    /// Compatibility is checked against the exact signed helper in this app,
    /// in addition to the XPC identity requirement and protocol schema.
    static func embeddedHelperCodeHash() throws -> String {
        let expectedIdentity = try requirement(for: helperIdentifier)
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/BenzoHelper")
        var code: SecStaticCode?
        var identity: SecRequirement?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(expectedIdentity as CFString, [], &identity) == errSecSuccess,
              let identity,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), identity) == errSecSuccess else {
            throw HelperIdentityError.invalidSigningIdentity
        }
        return try codeHash(code)
    }

    private static func codeHash(_ code: SecStaticCode) throws -> String {
        var rawInformation: CFDictionary?
        guard SecCodeCopySigningInformation(code, [], &rawInformation) == errSecSuccess,
              let information = rawInformation as? [String: Any],
              let hash = information[kSecCodeInfoUnique as String] as? Data,
              hash.count == 20 else {
            throw HelperIdentityError.invalidSigningIdentity
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    static func requirement(for identifier: String) throws -> String {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else {
            throw HelperIdentityError.invalidSigningIdentity
        }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
            throw HelperIdentityError.invalidSigningIdentity
        }
        var rawInformation: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation),
                                           &rawInformation) == errSecSuccess,
              let information = rawInformation as? [String: Any],
              let team = information[kSecCodeInfoTeamIdentifier as String] as? String,
              let ownIdentifier = information[kSecCodeInfoIdentifier as String] as? String,
              let flags = information[kSecCodeInfoFlags as String] as? NSNumber,
              flags.uint32Value & SecCodeSignatureFlags.runtime.rawValue != 0,
              flags.uint32Value & SecCodeSignatureFlags.adhoc.rawValue == 0 else {
            throw HelperIdentityError.invalidSigningIdentity
        }
        let ownRequirement = try requirement(for: ownIdentifier, teamIdentifier: team)
        var parsed: SecRequirement?
        guard SecRequirementCreateWithString(ownRequirement as CFString, [], &parsed) == errSecSuccess,
              let parsed,
              SecCodeCheckValidity(code, [], parsed) == errSecSuccess else {
            throw HelperIdentityError.invalidSigningIdentity
        }
        return try requirement(for: identifier, teamIdentifier: team)
    }

    /// A closed vocabulary prevents requirement-language injection. Team ID is
    /// obtained from this process's verified signature by the production caller.
    static func requirement(for identifier: String, teamIdentifier: String) throws -> String {
        guard [appIdentifier, helperIdentifier].contains(identifier),
              teamIdentifier.utf8.count == 10,
              teamIdentifier.utf8.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) }) else {
            throw HelperIdentityError.invalidSigningIdentity
        }
        let capability = identifier == appIdentifier ? "com.benzo.helper-client" : "com.benzo.helper-service"
        return "anchor apple generic" +
            " and certificate 1[field.1.2.840.113635.100.6.2.6] exists" +
            " and certificate leaf[field.1.2.840.113635.100.6.1.13] exists" +
            " and certificate leaf[subject.OU] = \"\(teamIdentifier)\"" +
            " and identifier \"\(identifier)\"" +
            " and entitlement[\"\(capability)\"] exists" +
            " and ! entitlement[\"com.apple.security.get-task-allow\"] exists" +
            " and ! entitlement[\"com.apple.security.cs.disable-library-validation\"] exists" +
            " and ! entitlement[\"com.apple.security.cs.allow-dyld-environment-variables\"] exists"
    }

    /// The UID comes from NSXPCConnection, never from the request body. A local
    /// GeneratedUID binds the grant to the account, including after UID reuse.
    static func localOwner(uid: UInt32) throws -> HelperOwner {
        guard uid >= 501, uid < UInt32.max else { throw HelperIdentityError.invalidLocalAccount }
        do {
            let node = try ODNode(session: ODSession.default(), type: ODNodeType(kODNodeTypeLocalNodes))
            let query = try ODQuery(node: node, forRecordTypes: kODRecordTypeUsers,
                attribute: kODAttributeTypeUniqueID, matchType: ODMatchType(kODMatchEqualTo),
                queryValues: String(uid), returnAttributes: [kODAttributeTypeUniqueID, kODAttributeTypeGUID],
                maximumResults: 2)
            guard let records = try query.resultsAllowingPartial(false) as? [ODRecord], records.count == 1 else {
                throw HelperIdentityError.invalidLocalAccount
            }
            let identifiers = try records[0].values(forAttribute: kODAttributeTypeUniqueID)
            let generatedIdentifiers = try records[0].values(forAttribute: kODAttributeTypeGUID)
            guard identifiers.count == 1, identifiers[0] as? String == String(uid),
                  generatedIdentifiers.count == 1,
                  let text = generatedIdentifiers[0] as? String, text.utf8.count == 36,
                  let generatedUID = UUID(uuidString: text) else {
                throw HelperIdentityError.invalidLocalAccount
            }
            return HelperOwner(uid: uid, generatedUID: generatedUID)
        } catch {
            throw HelperIdentityError.invalidLocalAccount
        }
    }
}
