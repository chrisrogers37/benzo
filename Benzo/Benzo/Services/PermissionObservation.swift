import Foundation

/// Evidence at the known legacy-rule location only. No case proves authorization,
/// correct scope, permission to mutate, or that other sudo configuration is absent.
enum PermissionObservation: Equatable {
    case noLegacyRule
    case legacyRulePresent
    case unknown(String)
}

/// The caller supplies metadata access and the exact path. No content reads,
/// command execution, preference updates, or live defaults belong to this observer.
struct PermissionObserver {
    let ruleURL: URL
    let metadata: (String) throws -> [FileAttributeKey: Any]

    func observe() -> PermissionObservation {
        guard ruleURL.isFileURL, ruleURL.pathComponents.count > 1 else {
            return .unknown("Legacy rule path is not a local file path.")
        }

        var candidate = URL(fileURLWithPath: "/", isDirectory: true)
        let components = ruleURL.pathComponents.dropFirst()
        do {
            guard try metadata(candidate.path)[.type] as? FileAttributeType == .typeDirectory else {
                return .unknown("Legacy rule parent is not a confirmed directory.")
            }
            for (index, component) in components.enumerated() {
                candidate.appendPathComponent(component)
                let attributes: [FileAttributeKey: Any]
                do {
                    attributes = try metadata(candidate.path)
                } catch {
                    // ENOENT is absence only after each preceding component was
                    // inspected as an ordinary directory, never a symlink.
                    if Self.isMissing(error as NSError) { return .noLegacyRule }
                    return .unknown(error.localizedDescription)
                }
                let isRule = index == components.count - 1
                let expectedType: FileAttributeType = isRule ? .typeRegular : .typeDirectory
                guard attributes[.type] as? FileAttributeType == expectedType else {
                    return .unknown("Legacy rule path contains an unexpected file type.")
                }
            }
            return .legacyRulePresent
        } catch {
            return .unknown(error.localizedDescription)
        }
    }

    private static func isMissing(_ error: NSError) -> Bool {
        if error.domain == NSPOSIXErrorDomain {
            return error.code == Int(POSIXError.Code.ENOENT.rawValue)
        }
        guard error.domain == NSCocoaErrorDomain, error.code == NSFileReadNoSuchFileError,
              let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError else {
            return false
        }
        return underlying.domain == NSPOSIXErrorDomain && underlying.code == Int(POSIXError.Code.ENOENT.rawValue)
    }
}
