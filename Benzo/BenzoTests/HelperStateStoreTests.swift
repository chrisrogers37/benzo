import Darwin
import Foundation
import XCTest

#if BENZO_STORAGE_TESTS
private let storageOwner = HelperOwner(uid: 501, generatedUID: UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!)
private let storageBoot = "11111111-1111-4111-8111-111111111111"

private final class HelperStorageFixture {
    let parent: URL
    var store: HelperStateStore?
    var directory: URL { parent.appendingPathComponent("com.benzo.helper", isDirectory: true) }
    var authority: URL { directory.appendingPathComponent("authority.json") }

    init() throws {
        parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("benzo-helper-store-\(UUID().uuidString)", isDirectory: true)
        guard mkdir(parent.path, mode_t(0o700)) == 0 else {
            throw HelperProtocolError.invalid("Could not create the owned storage fixture")
        }
    }

    deinit {
        store = nil
        try? FileManager.default.removeItem(at: parent)
    }

    func open(beforeBoundary: @escaping (HelperStoreBoundary) throws -> Void = { _ in }) throws {
        store = try HelperStateStore(testingParentDirectory: parent, beforeBoundary: beforeBoundary)
    }

    func enroll() throws -> HelperAuthorityState {
        let state = HelperAuthorityState(owner: storageOwner, revision: 0, lastExecution: nil)
        try store!.commit(state)
        return state
    }

    func intent(from state: HelperAuthorityState) -> HelperAuthorityState {
        var next = state
        next.revision += 1
        next.lastExecution = HelperExecutionFence(request: HelperWriteRequest(requestID: UUID(), operationID: UUID(),
            bootID: storageBoot, cell: ManagedCell(profile: .ac, key: .powernap), expectedValue: 1,
            target: 0, expectedRevision: state.revision))
        return next
    }

    func setACL(on url: URL, tag: acl_tag_t, permission: acl_perm_t,
                flags: [acl_flag_t] = []) throws {
        // This random principal is fixture-only; no account lookup or live-user
        // permission change is needed to exercise descriptor ACL validation.
        var principal = UUID().uuid
        var acl: acl_t? = acl_init(1)
        guard acl != nil else { throw HelperStorageInjectedFailure.boundary }
        defer { if let acl { acl_free(UnsafeMutableRawPointer(acl)) } }
        var entry: acl_entry_t?
        guard acl_create_entry(&acl, &entry) == 0, let entry,
              acl_set_tag_type(entry, tag) == 0,
              withUnsafeBytes(of: &principal, { acl_set_qualifier(entry, $0.baseAddress!) }) == 0,
              acl_set_permset_mask_np(entry, acl_permset_mask_t(permission.rawValue)) == 0 else {
            throw HelperStorageInjectedFailure.boundary
        }
        if !flags.isEmpty {
            var flagset: acl_flagset_t?
            guard acl_get_flagset_np(UnsafeMutableRawPointer(entry), &flagset) == 0, let flagset else {
                throw HelperStorageInjectedFailure.boundary
            }
            for flag in flags where acl_add_flag_np(flagset, flag) != 0 {
                throw HelperStorageInjectedFailure.boundary
            }
            guard acl_set_flagset_np(UnsafeMutableRawPointer(entry), flagset) == 0 else {
                throw HelperStorageInjectedFailure.boundary
            }
        }
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw HelperStorageInjectedFailure.boundary }
        defer { _ = Darwin.close(fd) }
        guard acl_set_fd_np(fd, acl!, ACL_TYPE_EXTENDED) == 0 else { throw HelperStorageInjectedFailure.boundary }
    }
}

private enum HelperStorageInjectedFailure: Error { case boundary }

final class HelperStateStoreTests: XCTestCase {
    func testExplicitUnenrolledStateSurvivesReopen() throws {
        let f = try HelperStorageFixture()
        try f.open()
        XCTAssertNil(try f.store!.load())
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.authority.path))
        f.store = nil
        try f.open()
        XCTAssertNil(try f.store!.load())
    }

    func testDurableEnrollmentIntentAndCompletionSurviveReopen() throws {
        let f = try HelperStorageFixture()
        try f.open()
        let enrolled = try f.enroll()
        let intent = f.intent(from: enrolled)
        try f.store!.commit(intent)
        f.store = nil
        try f.open()
        XCTAssertEqual(try f.store!.load(), intent)
        var completed = intent
        completed.lastExecution!.completedStatus = 0
        try f.store!.commit(completed)
        f.store = nil
        try f.open()
        XCTAssertEqual(try f.store!.load(), completed)
    }

    func testEstablishedMissingAuthorityCannotBecomeFirstRun() throws {
        let f = try HelperStorageFixture()
        try f.open()
        _ = try f.enroll()
        f.store = nil
        try FileManager.default.removeItem(at: f.authority)
        XCTAssertThrowsError(try f.open())
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.authority.path))
    }

    func testMalformedOrMissingEnvelopeFieldsAreRejected() throws {
        for bytes in ["not json", "{\"schema\":1}", "{\"schema\":2,\"state\":null}"] {
            let f = try HelperStorageFixture()
            try f.open()
            f.store = nil
            try Data(bytes.utf8).write(to: f.authority)
            XCTAssertThrowsError(try f.open(), bytes)
            XCTAssertEqual(try Data(contentsOf: f.authority), Data(bytes.utf8), "Malformed evidence must be preserved")
        }
    }

    func testSymlinkHardlinkAndUnsafeModesAreRejected() throws {
        for mutation in 0..<4 {
            let f = try HelperStorageFixture()
            try f.open()
            f.store = nil
            switch mutation {
            case 0:
                let saved = f.parent.appendingPathComponent("saved-authority.json")
                try FileManager.default.moveItem(at: f.authority, to: saved)
                XCTAssertEqual(symlink(saved.path, f.authority.path), 0)
            case 1:
                XCTAssertEqual(link(f.authority.path, f.parent.appendingPathComponent("hardlink.json").path), 0)
            case 2: XCTAssertEqual(chmod(f.authority.path, mode_t(0o644)), 0)
            default: XCTAssertEqual(chmod(f.directory.path, mode_t(0o755)), 0)
            }
            XCTAssertThrowsError(try f.open(), "Unsafe evidence case \(mutation)")
        }
    }

    func testLockIsExclusiveAndMissingEstablishedLockIsRejected() throws {
        let f = try HelperStorageFixture()
        try f.open()
        XCTAssertThrowsError(try HelperStateStore(testingParentDirectory: f.parent))
        f.store = nil
        let lock = f.directory.appendingPathComponent("authority.lock")
        try FileManager.default.removeItem(at: lock)
        XCTAssertThrowsError(try f.open())
        XCTAssertFalse(FileManager.default.fileExists(atPath: lock.path), "Do not recreate a missing stable lock")
    }

    func testOwnerTransferAndRevisionReplacementCannotOverwriteEvidence() throws {
        let f = try HelperStorageFixture()
        try f.open()
        let enrolled = try f.enroll()
        let replacement = HelperAuthorityState(owner: HelperOwner(uid: 502, generatedUID: UUID()),
            revision: 0, lastExecution: nil)
        XCTAssertThrowsError(try f.store!.commit(replacement))
        let intent = f.intent(from: enrolled)
        try f.store!.commit(intent)
        XCTAssertThrowsError(try f.store!.commit(enrolled))
        XCTAssertThrowsError(try f.store!.commit(f.intent(from: enrolled)), "Same revision cannot replace the request")
        XCTAssertEqual(try f.store!.load(), intent)
    }

    func testInterruptedAdmissionBoundariesFenceReopen() throws {
        for boundary in HelperStoreBoundary.allCases {
            let f = try HelperStorageFixture()
            var armed = false
            try f.open { reached in
                if armed && reached == boundary { throw HelperStorageInjectedFailure.boundary }
            }
            let enrolled = try f.enroll()
            armed = true
            XCTAssertThrowsError(try f.store!.commit(f.intent(from: enrolled)), "Boundary \(boundary)")
            f.store = nil
            XCTAssertThrowsError(try f.open(), "Interrupted \(boundary) must retain uncertainty evidence")
        }
    }

    func testFailedCompletionAfterRenameNeverLoadsCompleted() throws {
        for boundary in [HelperStoreBoundary.directorySync, .directoryFullSync] {
            let f = try HelperStorageFixture()
            var armed = false
            var occurrences = 0
            try f.open { reached in
                if armed && reached == boundary {
                    occurrences += 1
                    // First synchronizes pending evidence; second follows the
                    // authority rename. The new completed bytes are now visible.
                    if occurrences == 2 { throw HelperStorageInjectedFailure.boundary }
                }
            }
            let intent = f.intent(from: try f.enroll())
            try f.store!.commit(intent)
            var completed = intent
            completed.lastExecution!.completedStatus = 0
            armed = true
            XCTAssertThrowsError(try f.store!.commit(completed))
            let visible = try String(contentsOf: f.authority, encoding: .utf8)
            XCTAssertTrue(visible.contains("completedStatus"), "Fixture must cross the completed rename")
            XCTAssertTrue(FileManager.default.fileExists(atPath: f.directory.appendingPathComponent("commit-pending.json").path))
            f.store = nil
            XCTAssertThrowsError(try f.open(), "Visible completion is not committed completion")
        }
    }

    func testManagedEvidenceRejectsExtendedACLsDespitePrivateModes() throws {
        for directory in [false, true] {
            for inherited in [false, true] {
                let f = try HelperStorageFixture()
                try f.open()
                f.store = nil
                let url = directory ? f.directory : f.authority
                try f.setACL(on: url, tag: ACL_EXTENDED_ALLOW, permission: ACL_READ_DATA,
                             flags: inherited ? [ACL_ENTRY_INHERITED] : [])
                var metadata = stat()
                XCTAssertEqual(lstat(url.path, &metadata), 0)
                XCTAssertEqual(metadata.st_mode & 0o7777, mode_t(directory ? 0o700 : 0o600))
                XCTAssertThrowsError(try f.open(), "Even a read grant violates private evidence")
            }
        }
    }

    func testAncestorMutatingACLsAreRejectedIncludingInheritanceOnlyGrants() throws {
        let permissions: [acl_perm_t] = [ACL_WRITE_DATA, ACL_APPEND_DATA, ACL_DELETE, ACL_DELETE_CHILD,
            ACL_WRITE_ATTRIBUTES, ACL_WRITE_EXTATTRIBUTES, ACL_WRITE_SECURITY, ACL_CHANGE_OWNER]
        for permission in permissions {
            for inheritedOnly in [false, true] {
                let f = try HelperStorageFixture()
                try f.setACL(on: f.parent, tag: ACL_EXTENDED_ALLOW, permission: permission,
                    flags: inheritedOnly ? [ACL_ENTRY_FILE_INHERIT, ACL_ENTRY_DIRECTORY_INHERIT, ACL_ENTRY_ONLY_INHERIT] : [])
                XCTAssertThrowsError(try f.open(), "A mutating ancestor grant cannot be ignored")
                XCTAssertFalse(FileManager.default.fileExists(atPath: f.directory.path))
            }
        }
    }

    func testAncestorReadOnlyAllowAndNormalDenyRemainSupported() throws {
        for denied in [false, true] {
            let f = try HelperStorageFixture()
            try f.setACL(on: f.parent, tag: denied ? ACL_EXTENDED_DENY : ACL_EXTENDED_ALLOW,
                         permission: denied ? ACL_DELETE : ACL_READ_DATA)
            try f.open()
            XCTAssertNil(try f.store!.load())
        }
    }
}
#endif
