import Darwin
import Foundation
import XCTest

#if BENZO_STORAGE_TESTS
private enum CommandStorageFailure: Error { case injected }

private final class CommandStorageFixture {
    let parent: URL
    let initial = try! PowerCommandState.initial(owner: PowerCommandOwner(uid: 501, generatedUID: UUID()))
    var store: PowerCommandStore?
    var directory: URL { parent.appendingPathComponent(PowerCommandStore.directoryName, isDirectory: true) }
    var authority: URL { directory.appendingPathComponent(PowerCommandStore.stateName) }
    var lock: URL { directory.appendingPathComponent(PowerCommandStore.lockName) }

    init() throws {
        parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("benzo-command-store-\(UUID().uuidString)", isDirectory: true)
        guard mkdir(parent.path, mode_t(0o700)) == 0 else { throw CommandStorageFailure.injected }
    }

    deinit { store = nil; try? FileManager.default.removeItem(at: parent) }

    func open(create: Bool = false,
              beforeBoundary: @escaping (PowerCommandStoreBoundary) throws -> Void = { _ in }) throws {
        store = try PowerCommandStore(testingParentDirectory: parent,
            initialState: create ? initial : nil, beforeBoundary: beforeBoundary)
    }

    func intent(sequence: UInt64 = 1) -> PowerCommandState {
        var next = initial
        next.highWaterMark = sequence
        next.pending = PowerCommandReceipt(request: PowerCommandRequest(grantEpoch: initial.grantEpoch,
            sequence: sequence, requestID: UUID(), operationID: UUID(), bootID: UUID(),
            profile: .ac, key: .powernap, expectedValue: 1, target: 0), outcome: .intent)
        return next
    }

    func setReadACL(_ url: URL) throws {
        var principal = UUID().uuid
        var acl: acl_t? = acl_init(1)
        guard acl != nil else { throw CommandStorageFailure.injected }
        defer { if let acl { acl_free(UnsafeMutableRawPointer(acl)) } }
        var entry: acl_entry_t?
        guard acl_create_entry(&acl, &entry) == 0, let entry,
              acl_set_tag_type(entry, ACL_EXTENDED_ALLOW) == 0,
              withUnsafeBytes(of: &principal, { acl_set_qualifier(entry, $0.baseAddress!) }) == 0,
              acl_set_permset_mask_np(entry, acl_permset_mask_t(ACL_READ_DATA.rawValue)) == 0 else {
            throw CommandStorageFailure.injected
        }
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw CommandStorageFailure.injected }
        defer { _ = Darwin.close(fd) }
        guard acl_set_fd_np(fd, acl!, ACL_TYPE_EXTENDED) == 0 else { throw CommandStorageFailure.injected }
    }
}

final class CommandToolStateStoreTests: XCTestCase {
    func testInitializationIsExplicitAndNeverReplacesExistingGrant() throws {
        let f = try CommandStorageFixture()
        XCTAssertThrowsError(try f.open())
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.directory.path))
        try f.open(create: true)
        XCTAssertEqual(try f.store!.load(), f.initial)
        f.store = nil
        XCTAssertThrowsError(try f.open(create: true))
        try f.open()
        XCTAssertEqual(try f.store!.load(), f.initial)
    }

    func testIntentTerminalAndAckPersistAcrossProcessLifetimes() throws {
        let f = try CommandStorageFixture()
        try f.open(create: true)
        var next = f.intent()
        try f.store!.commit(next)
        f.store = nil; try f.open()
        XCTAssertEqual(try f.store!.load(), next)
        next.pending!.outcome = .completed(exitStatus: 0)
        try f.store!.commit(next)
        f.store = nil; try f.open()
        XCTAssertEqual(try f.store!.load(), next)
        next.pending = nil
        try f.store!.commit(next)
        f.store = nil; try f.open()
        XCTAssertEqual(try f.store!.load(), next)
        XCTAssertEqual(try f.store!.load().highWaterMark, 1)
    }

    func testMissingEstablishedAuthorityOrLockNeverBecomesFreshState() throws {
        for removeLock in [false, true] {
            let f = try CommandStorageFixture()
            try f.open(create: true)
            f.store = nil
            let removed = removeLock ? f.lock : f.authority
            try FileManager.default.removeItem(at: removed)
            XCTAssertThrowsError(try f.open())
            XCTAssertThrowsError(try f.open(create: true))
            XCTAssertFalse(FileManager.default.fileExists(atPath: removed.path))
        }
    }

    func testMalformedOrMissingReceiptEvidenceIsRejectedWithoutRepair() throws {
        let f = try CommandStorageFixture()
        try f.open(create: true)
        f.store = nil
        let json = String(decoding: try JSONEncoder().encode(f.initial), as: UTF8.self)
        let payloads = ["not json", "{\"schema\":1}",
            json.replacingOccurrences(of: "\"pending\":null,", with: "")
                .replacingOccurrences(of: ",\"pending\":null", with: ""),
            json.replacingOccurrences(of: "\"schema\":1", with: "\"schema\":2")]
        for payload in payloads {
            try Data(payload.utf8).write(to: f.authority)
            XCTAssertThrowsError(try f.open())
            XCTAssertEqual(try Data(contentsOf: f.authority), Data(payload.utf8))
        }
    }

    func testUnsafeFileTypesLinksModesAndDirectoryLinksAreRejected() throws {
        for mutation in 0..<8 {
            let f = try CommandStorageFixture()
            try f.open(create: true)
            f.store = nil
            switch mutation {
            case 0:
                let saved = f.parent.appendingPathComponent("saved.json")
                try FileManager.default.moveItem(at: f.authority, to: saved)
                XCTAssertEqual(symlink(saved.path, f.authority.path), 0)
            case 1:
                XCTAssertEqual(link(f.authority.path, f.parent.appendingPathComponent("hardlink.json").path), 0)
            case 2: XCTAssertEqual(chmod(f.authority.path, mode_t(0o644)), 0)
            case 3: XCTAssertEqual(chmod(f.directory.path, mode_t(0o755)), 0)
            case 4:
                try FileManager.default.removeItem(at: f.authority)
                XCTAssertEqual(mkfifo(f.authority.path, mode_t(0o600)), 0)
            case 5:
                try FileManager.default.removeItem(at: f.authority)
                XCTAssertEqual(mkdir(f.authority.path, mode_t(0o700)), 0)
            case 6:
                let saved = f.parent.appendingPathComponent("saved-directory")
                try FileManager.default.moveItem(at: f.directory, to: saved)
                XCTAssertEqual(symlink(saved.path, f.directory.path), 0)
            default: XCTAssertEqual(chmod(f.lock.path, mode_t(0o660)), 0)
            }
            XCTAssertThrowsError(try f.open(), "Unsafe case \(mutation)")
        }
    }

    func testExtendedACLsCannotOverridePrivateEvidenceModes() throws {
        for directory in [false, true] {
            let f = try CommandStorageFixture()
            try f.open(create: true)
            f.store = nil
            try f.setReadACL(directory ? f.directory : f.authority)
            XCTAssertThrowsError(try f.open())
        }
    }

    func testExclusiveLockAndDescriptorIdentityAreRequiredThroughoutLifetime() throws {
        let f = try CommandStorageFixture()
        try f.open(create: true)
        XCTAssertThrowsError(try PowerCommandStore(testingParentDirectory: f.parent))
        let original = f.directory.appendingPathComponent("saved-lock")
        try FileManager.default.moveItem(at: f.lock, to: original)
        let fd = Darwin.open(f.lock.path, O_WRONLY | O_CREAT | O_EXCL, mode_t(0o600))
        XCTAssertGreaterThanOrEqual(fd, 0)
        if fd >= 0 { _ = Darwin.close(fd) }
        XCTAssertThrowsError(try f.store!.load())
        XCTAssertThrowsError(try f.store!.commit(f.intent()))
    }

    func testStoreRejectsGrantTransferRewindAndIntentDiscard() throws {
        let f = try CommandStorageFixture()
        try f.open(create: true)
        let foreign = try PowerCommandState.initial(owner: PowerCommandOwner(uid: 502, generatedUID: UUID()),
                                                    grantEpoch: f.initial.grantEpoch)
        XCTAssertThrowsError(try f.store!.commit(foreign))
        XCTAssertThrowsError(try f.store!.commit(PowerCommandState.initial(owner: f.initial.owner)))
        let intent = f.intent()
        try f.store!.commit(intent)
        XCTAssertThrowsError(try f.store!.commit(f.initial))
        XCTAssertThrowsError(try f.store!.commit(f.intent()))
        var discarded = intent
        discarded.pending = nil
        XCTAssertThrowsError(try f.store!.commit(discarded))
        XCTAssertEqual(try f.store!.load(), intent)
    }

    func testEveryInterruptedCommitBoundaryPreservesAFailClosedMarker() throws {
        for boundary in PowerCommandStoreBoundary.allCases {
            let f = try CommandStorageFixture()
            var armed = false
            try f.open(create: true) { reached in
                if armed && reached == boundary { throw CommandStorageFailure.injected }
            }
            armed = true
            XCTAssertThrowsError(try f.store!.commit(f.intent()), "Boundary \(boundary)")
            f.store = nil
            XCTAssertThrowsError(try f.open(), "Interrupted \(boundary) cannot permit dispatch or invent completion")
        }
    }

    func testPostRenameFailureCannotExposeUncommittedTerminalProofOnReopen() throws {
        for boundary in [PowerCommandStoreBoundary.directorySync, .directoryFullSync] {
            let f = try CommandStorageFixture()
            var armed = false
            var occurrences = 0
            try f.open(create: true) { reached in
                if armed && reached == boundary {
                    occurrences += 1
                    if occurrences == 2 { throw CommandStorageFailure.injected }
                }
            }
            var next = f.intent()
            try f.store!.commit(next)
            next.pending!.outcome = .completed(exitStatus: 0)
            armed = true
            XCTAssertThrowsError(try f.store!.commit(next))
            let visible = try String(contentsOf: f.authority, encoding: .utf8)
            XCTAssertTrue(visible.contains("completed"), "Failure must cross the completion rename")
            XCTAssertTrue(FileManager.default.fileExists(atPath: f.directory.appendingPathComponent("commit-pending.json").path))
            f.store = nil
            XCTAssertThrowsError(try f.open())
        }
    }

    func testOversizedAndUnexpectedEvidenceIsPreservedAndRejected() throws {
        for oversized in [false, true] {
            let f = try CommandStorageFixture()
            try f.open(create: true)
            f.store = nil
            if oversized { try Data(repeating: 32, count: 16_385).write(to: f.authority) }
            else { try Data("interrupted".utf8).write(to: f.directory.appendingPathComponent(".leftover.tmp")) }
            XCTAssertThrowsError(try f.open())
        }
    }
}
#endif
