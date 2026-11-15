import Foundation
import OpenDirectory
import Security

/// Shared by the app and daemon. No ad-hoc or unsigned development exception is
/// accepted by the privileged transport; tests use the pure requirement builder.
enum HelperIdentity {
    static let appIdentifier = HelperCodeRequirement.appIdentifier
    static let helperIdentifier = HelperCodeRequirement.helperIdentifier

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

    static func requirement(for identifier: String, teamIdentifier: String) throws -> String {
        try HelperCodeRequirement.requirement(for: identifier, teamIdentifier: teamIdentifier)
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
