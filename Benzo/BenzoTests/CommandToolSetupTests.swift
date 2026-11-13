import Darwin
import Foundation
import XCTest

final class CommandToolSetupTests: XCTestCase {
    private let owner = PowerCommandOwner(uid: 501,
        generatedUID: UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!)
    private let digest = String(repeating: "a", count: 64)

    func testShellQuotingPreservesSpacesApostrophesAndShellMetacharacters() throws {
        let values = ["/Applications/Benzo App.app/tool", "/Users/test/Benzo's app/tool",
                      "/tmp/$(echo unsafe)`echo unsafe`\\$HOME; & | > < * ? (test)/tool"]
        for value in values {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", "printf '%s' " + CommandToolSetup.shellWord(value)]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try process.run()
            try pipe.fileHandleForWriting.close()
            let actual = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
            XCTAssertEqual(actual, Data(value.utf8))
        }
    }

    func testBootstrapRejectsControlCharactersRelativePathsAndInvalidDigests() {
        for path in ["relative/tool", "/tmp/tool\nother", "/tmp/tool\r", "/tmp/tool\0", "/tmp/tool\t"] {
            XCTAssertThrowsError(try CommandToolSetup.bootstrap(action: .install, sourcePath: path, owner: owner, digest: digest))
        }
        for bad in ["", "a", String(repeating: "A", count: 64), digest + "0", String(repeating: "g", count: 64)] {
            XCTAssertThrowsError(try CommandToolSetup.bootstrap(action: .install, sourcePath: "/tmp/tool", owner: owner, digest: bad))
        }
    }

    func testBootstrapPinsStagedBytesBeforeInvokingAnyCandidateCode() throws {
        let command = try CommandToolSetup.bootstrap(action: .install, sourcePath: "/tmp/source app/tool", owner: owner, digest: digest)
        XCTAssertTrue(command.hasPrefix("/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin /bin/sh -c "))
        let hash = try XCTUnwrap(command.range(of: "/usr/bin/shasum -a 256"))
        let execute = try XCTUnwrap(command.range(of: "\"$stage/tool\" \"$3\""))
        XCTAssertLessThan(hash.lowerBound, execute.lowerBound)
        XCTAssertTrue(command.contains("/private/var/tmp/com.benzo.command.XXXXXXXX"))
        XCTAssertTrue(command.contains("'install-v1' '501' '\(owner.generatedUID.uuidString)'"))
        XCTAssertFalse(command.contains("sudo"))
        XCTAssertFalse(command.contains("pmset"))
    }

    func testApprovalNamesExactBeneficiaryAndDigestForEveryAdministrativeAction() throws {
        for action in CommandToolSetup.Action.allCases {
            let script = try CommandToolSetup.appleScript(action: action, sourcePath: "/tmp/Benzo's app/tool",
                owner: owner, accountName: "standard-user", digest: digest)
            XCTAssertTrue(script.contains("with prompt"))
            XCTAssertTrue(script.contains("UID 501"))
            XCTAssertTrue(script.contains(owner.generatedUID.uuidString))
            XCTAssertTrue(script.contains(digest))
            XCTAssertTrue(script.contains("administrator approving this does not become"))
            XCTAssertTrue(script.hasSuffix("with administrator privileges"))
            XCTAssertFalse(script.contains(" password "))
        }
    }

    func testInterruptedTransactionRecognizesOnlyItsExactGenerationsAndAccount() throws {
        let epoch = UUID()
        let before = Data("approved old tool".utf8), after = Data("approved new tool".utf8)
        let oldPolicy = try CommandInstaller.policy(owner: owner, digest: CommandToolIdentity.digest(before))
        let newPolicy = try CommandInstaller.policy(owner: owner, digest: CommandToolIdentity.digest(after))
        let transaction = CommandInstaller.Transaction(owner: owner, grantEpoch: epoch, oldTool: before,
            oldPolicy: oldPolicy, newTool: after, newPolicy: newPolicy)
        let persisted = try JSONDecoder().decode(CommandInstaller.Transaction.self, from: JSONEncoder().encode(transaction))
        XCTAssertTrue(persisted.admits(tool: after, policy: oldPolicy, owner: owner, epoch: epoch))
        XCTAssertTrue(persisted.admits(tool: before, policy: nil, owner: owner, epoch: epoch))
        XCTAssertTrue(persisted.admits(tool: after, policy: newPolicy, owner: owner, epoch: epoch))
        XCTAssertFalse(persisted.admits(tool: Data("foreign executable".utf8), policy: oldPolicy, owner: owner, epoch: epoch))
        XCTAssertFalse(persisted.admits(tool: after, policy: Data("ALL=(ALL) ALL".utf8), owner: owner, epoch: epoch))
        XCTAssertFalse(persisted.admits(tool: after, policy: newPolicy, owner: owner, epoch: UUID()))
        XCTAssertFalse(persisted.admits(tool: nil, policy: oldPolicy, owner: owner, epoch: epoch))
        let otherOwner = PowerCommandOwner(uid: owner.uid, generatedUID: UUID())
        XCTAssertFalse(persisted.admits(tool: after, policy: oldPolicy, owner: otherOwner, epoch: epoch))
    }

    func testPolicyLimitsGrantToFiveExactDigestBoundVerbs() throws {
        let data = try CommandInstaller.policy(owner: owner, digest: digest)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains("#501 ALL=(root) NOPASSWD: NOSETENV:"))
        XCTAssertTrue(text.contains("Defaults!\(CommandToolIdentity.installedPath) stay_setuid,env_reset,!setenv"))
        for verb in PowerCommandVerb.allCases {
            XCTAssertTrue(text.contains("sha256:\(digest) \(CommandToolIdentity.installedPath) \(verb.rawValue)"))
        }
        XCTAssertEqual(text.components(separatedBy: "sha256:").count - 1, 5)
        for forbidden in ["install-v1", "repair-v1", "remove-v1", "%admin", "pmset", "*", "ALL=(ALL)"] {
            XCTAssertFalse(text.contains(forbidden))
        }
    }

    func testRenderedPolicyParsesWithoutChangingSystemPolicy() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("benzo-policy-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let candidate = directory.appendingPathComponent("candidate")
        try CommandInstaller.policy(owner: owner, digest: digest).write(to: candidate)
        let result = CommandRuntime.run(executable: "/usr/sbin/visudo", arguments: ["-c", "-f", candidate.path],
                                        timeout: 5, maximumBytes: 8_192)
        XCTAssertTrue(result.succeeded, String(data: result.stderr, encoding: .utf8) ?? "visudo failed")
    }

    func testRuntimeReapsNormalAndTimedOutOwnedChildren() throws {
        let success = CommandRuntime.run(executable: "/usr/bin/printf", arguments: ["fixture"], timeout: 2, maximumBytes: 100)
        XCTAssertTrue(success.succeeded)
        XCTAssertEqual(success.stdout, Data("fixture".utf8))
        let timeout = CommandRuntime.run(executable: "/bin/sleep", arguments: ["2"], timeout: 0.05, maximumBytes: 100)
        XCTAssertTrue(timeout.spawned)
        XCTAssertTrue(timeout.reaped)
        XCTAssertFalse(timeout.complete)
        XCTAssertNil(timeout.exitStatus)
        let missing = CommandRuntime.run(executable: "/does-not-exist/benzo-owned-fixture", arguments: [], timeout: 1, maximumBytes: 100)
        XCTAssertFalse(missing.spawned)
    }
}
