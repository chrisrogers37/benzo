import Foundation
import Security

enum HelperEnrollmentError: LocalizedError {
    case denied(OSStatus)

    var errorDescription: String? {
        switch self {
        case .denied(let status) where status == errAuthorizationCanceled:
            return "Authorization was canceled. This account has not been granted access."
        case .denied:
            return "macOS did not authorize this account's setup. Try setup again when an administrator is available."
        }
    }
}

/// Construct only after the user chooses the explicit account-enrollment action.
/// Keep this object alive until the helper replies (or the request is abandoned).
/// It is never persisted and does not perform any command or change the auth DB.
final class HelperEnrollmentAuthorization: @unchecked Sendable {
    private var reference: AuthorizationRef?
    let externalForm: Data

    init() throws {
        var created: AuthorizationRef?
        let status = AuthorizationCreate(nil, nil, [], &created)
        guard status == errAuthorizationSuccess, let created else {
            throw HelperEnrollmentError.denied(status)
        }
        do {
            let result = Self.withRight { rights in
                AuthorizationCopyRights(created, rights, nil, [.interactionAllowed, .extendRights], nil)
            }
            guard result == errAuthorizationSuccess else { throw HelperEnrollmentError.denied(result) }
            var form = AuthorizationExternalForm()
            let exported = AuthorizationMakeExternalForm(created, &form)
            guard exported == errAuthorizationSuccess else { throw HelperEnrollmentError.denied(exported) }
            externalForm = withUnsafeBytes(of: &form) { Data($0) }
            reference = created
        } catch {
            AuthorizationFree(created, [.destroyRights])
            throw error
        }
    }

    deinit {
        if let reference { AuthorizationFree(reference, [.destroyRights]) }
    }

    /// Must run only after authenticating the XPC peer. This authorizes enrollment,
    /// not the identity of its beneficiary; the beneficiary is the verified peer.
    /// No interaction and no extension are allowed in the root daemon.
    static func validate(_ data: Data) -> Bool {
        guard data.count == MemoryLayout<AuthorizationExternalForm>.size else { return false }
        var form = AuthorizationExternalForm()
        _ = withUnsafeMutableBytes(of: &form) { data.copyBytes(to: $0) }
        var reference: AuthorizationRef?
        guard AuthorizationCreateFromExternalForm(&form, &reference) == errAuthorizationSuccess,
              let reference else { return false }
        defer { AuthorizationFree(reference, []) }
        return withRight { rights in
            AuthorizationCopyRights(reference, rights, nil, [], nil) == errAuthorizationSuccess
        }
    }

    private static func withRight<T>(_ body: (UnsafePointer<AuthorizationRights>) -> T) -> T {
        // Apple exposes this built-in administrator right as kAuthorizationRightExecute.
        // We use it solely to approve the lasting, narrow owner grant; no deprecated
        // AuthorizationExecuteWithPrivileges or broad command endpoint is involved.
        kAuthorizationRightExecute.withCString { name in
            var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &item) { itemPointer in
                var rights = AuthorizationRights(count: 1, items: itemPointer)
                return withUnsafePointer(to: &rights, body)
            }
        }
    }
}
