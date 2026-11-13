import Foundation

/// Interactive setup is reached only after an explicit user action. The system
/// prompt approves the named beneficiary and exact executable digest. It does
/// not claim AppleScript preserved the initiating UID across elevation.
struct CommandToolSetup {
    // Apple DTS documents serial secondary-thread use of NSAppleScript. Keep
    // creation and execution together here; no cancellation may abandon setup.
    private static let approvalQueue = DispatchQueue(label: "benzo.command.setup")
    enum Action: String, CaseIterable {
        case install = "install-v1", replace = "repair-v1", remove = "remove-v1"
    }

    // Kept as an injectable composition seam; setup intentionally does not use
    // CommandRunner's bounded child-return semantics for an elevated installer.
#if !BENZO_STORAGE_TESTS
    init(runner: CommandRunner = CommandRunner()) {}

    func perform(_ action: Action) async throws {
        let owner = try CommandToolIdentity.currentOwner()
        let name = try CommandToolIdentity.localAccountName(uid: owner.uid)
        let source = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/BenzoCommand").path
        let digest = CommandToolIdentity.digest(try CommandToolIdentity.executableBytes(at: source))
        let script = try Self.appleScript(action: action, sourcePath: source,
                                          owner: owner, accountName: name, digest: digest)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Self.approvalQueue.async {
                do {
                    guard let command = NSAppleScript(source: script) else {
                        throw PowerCommandError.invalid("Benzo could not prepare the administrator approval.")
                    }
                    var error: NSDictionary?
                    _ = command.executeAndReturnError(&error)
                    if let error {
                        let code = error[NSAppleScript.errorNumber] as? Int
                        if code == -128 {
                            throw PowerCommandError.invalid("Setup was canceled. Existing access and recovery records were retained.")
                        }
                        let message = error[NSAppleScript.errorMessage] as? String
                        throw PowerCommandError.invalid(PowerCommandWire.reason(message ??
                            "The administrator setup did not complete. Existing recovery records were retained."))
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
#endif

    static func appleScript(action: Action, sourcePath: String, owner: PowerCommandOwner,
                            accountName: String, digest: String) throws -> String {
        let command = try bootstrap(action: action, sourcePath: sourcePath, owner: owner, digest: digest)
        guard !accountName.isEmpty, accountName.utf8.count <= 256,
              accountName.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw PowerCommandError.invalid("The setup account name is invalid.")
        }
        let operation = action == .remove ? "Remove" : (action == .replace ? "Replace" : "Install")
        let prompt = "\(operation) Benzo's power command for local account \(accountName) " +
            "(UID \(owner.uid), ID \(owner.generatedUID.uuidString)). " +
            "This account's programs can use Benzo's limited power-setting commands. " +
            "The administrator approving this does not become the authorized account. " +
            "Tool SHA-256: \(digest)."
        return "do shell script \(appleScriptLiteral(command)) with prompt \(appleScriptLiteral(prompt)) with administrator privileges"
    }

    static func bootstrap(action: Action, sourcePath: String, owner: PowerCommandOwner,
                          digest: String) throws -> String {
        try owner.validate()
        guard owner.uid >= 501, owner.uid < UInt32.max,
              sourcePath.hasPrefix("/"), sourcePath.utf8.count <= 4_096,
              !sourcePath.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              validDigest(digest) else {
            throw PowerCommandError.invalid("The setup path, account or executable digest is invalid.")
        }
        // Only Apple-provided fixed utilities execute before the staged bytes
        // pass their hash. There is no second read of an app-owned script.
        let recipe = #"""
        set -eu
        umask 077
        stage=$(/usr/bin/mktemp -d /private/var/tmp/com.benzo.command.XXXXXXXX)
        trap '/bin/rm -f "$stage/tool"; /bin/rmdir "$stage"' EXIT
        /bin/chmod -N "$stage"
        /bin/chmod 0700 "$stage"
        /bin/cp -X "$1" "$stage/tool"
        /usr/sbin/chown 0:0 "$stage/tool"
        /bin/chmod -N "$stage/tool"
        /bin/chmod 0700 "$stage/tool"
        actual=$(/usr/bin/shasum -a 256 "$stage/tool")
        actual=${actual%% *}
        [ "$actual" = "$2" ] || { /bin/echo 'Benzo command bytes changed before approval completed.' >&2; exit 65; }
        "$stage/tool" "$3" "$4" "$5" "$2"
        """#
        let words = [recipe, "benzo-setup", sourcePath, digest, action.rawValue,
                     String(owner.uid), owner.generatedUID.uuidString]
        return "/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin /bin/sh -c " +
            words.map(shellWord).joined(separator: " ")
    }

    static func validDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    static func shellWord(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func appleScriptLiteral(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n") + "\""
    }
}
