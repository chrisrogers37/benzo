import Foundation
import Darwin
import XCTest

final class RecoveryStorageTests: XCTestCase {
    private let host = "11111111-1111-4111-8111-111111111111"
    private let boot = "22222222-2222-4222-8222-222222222222"
    private let laterBoot = "33333333-3333-4333-8333-333333333333"
    private let cell = ManagedCell(profile: .ac, key: .powernap)

    func testProfileCaptureKeepsDistinctProfilesAndRejectsMalformedManagedEvidence() throws {
        let capture = try ProfileSnapshot(parsing: """
        UPS Power:
         powernap 1
        AC Power:
         powernap\t1
         Sleep On Power Button 1
         hibernatefile /var/vm/sleepimage
        Battery Power:
         powernap 0
        """)
        XCTAssertEqual(capture.profiles, [.ac, .battery, .ups])
        XCTAssertEqual(capture.value(for: cell), 1)
        XCTAssertEqual(capture.value(for: ManagedCell(profile: .battery, key: .powernap)), 0)
        XCTAssertNil(capture.value(for: ManagedCell(profile: .ac, key: .hibernatemode)))
        for malformed in [
            "", "AC Power:\npowernap 2", "AC Power:\npowernap ０", "AC Power:\npowernap 1 suffix",
            "AC Power:\npowernap 1\npowernap 0", "AC Power:\npowernap 1\nAC Power:\npowernap 0",
            "Other Power:\npowernap 1", "AC Power:\nhibernatemode 7", "AC Power:\npowernap -1"
        ] {
            XCTAssertThrowsError(try ProfileSnapshot(parsing: malformed))
        }
    }

    func testDecodedSchemaAndMissingNullableEvidenceAreNotDefaulted() throws {
        let journal = try initialJournal()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(journal)) as? [String: Any])
        json["schema"] = 2
        let decoded = try JSONDecoder().decode(RecoveryJournal.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.schema, 2)
        XCTAssertThrowsError(try decoded.validate(uid: getuid(), hostID: host))
        json["schema"] = 1
        json.removeValue(forKey: "operation")
        XCTAssertThrowsError(try JSONDecoder().decode(RecoveryJournal.self, from: JSONSerialization.data(withJSONObject: json)))

        var pending = try intendedJournal()
        pending.operation = RecoveryOperation(id: UUID(), bootID: "not-a-boot", kind: .apply,
            preState: [CellValue(cell: cell, value: 1)],
            steps: [RecoveryStep(cell: cell, precondition: 1, target: 0, phase: .intended)])
        XCTAssertThrowsError(try pending.validate(uid: getuid(), hostID: host))
    }

    func testLockReceiptRetryAndNewSessionRetainOriginals() throws {
        try withScratch { directory in
            let store = makeStore(directory)
            try store.acquireLock()
            XCTAssertNil(try store.loadJournal())
            let competitor = makeStore(directory)
            XCTAssertThrowsError(try competitor.acquireLock())
            var journal = try initialJournal()
            try store.commitJournal(journal)
            XCTAssertEqual(try store.loadJournal(), journal)
            journal.cells[0].owned = false
            journal.cells[0].observed = 1
            journal.resolvedAt = journal.capturedAt.addingTimeInterval(1)
            journal.revision += 1
            try store.commitJournal(journal)
            XCTAssertThrowsError(try store.loadJournal()) { error in
                guard case RecoveryEvidenceError.receiptRequired(let retained) = error else {
                    return XCTFail("Expected actionable receipt retry, got \(error)")
                }
                XCTAssertEqual(retained, journal)
            }
            try store.commitJournal(journal)
            try store.saveResolvedReceipt(journal)
            XCTAssertEqual(try store.loadJournal(), journal)
            let next = try initialJournal()
            try store.commitJournal(next)
            XCTAssertEqual(try store.loadJournal(), next)
            let previous = try readJournalFile(directory, name: "recovery-journal.previous.json")
            XCTAssertEqual(previous, journal)
        }
    }

    func testAllJournalPersistenceBoundariesPreserveCapturedOriginals() throws {
        let boundaries: [PersistenceBoundary] = [
            .write, .fileSync, .fileFullSync, .fileClose, .previousRename,
            .rename, .directorySync, .directoryFullSync, .directoryClose
        ]
        for boundary in boundaries {
            try withScratch { directory in
                var armed = false
                let store = makeStore(directory) {
                    if armed && $0 == boundary { throw InjectedFailure.persistence }
                }
                try store.acquireLock()
                var journal = try initialJournal()
                try store.commitJournal(journal)
                armed = true
                journal.revision += 1
                XCTAssertThrowsError(try store.commitJournal(journal), "Boundary \(boundary)")
                let retained = try readJournalFile(directory, name: "recovery-journal.json")
                XCTAssertEqual(retained.capture, journal.capture, "Boundary \(boundary)")
                XCTAssertEqual(retained.cells[0].original, 1, "Boundary \(boundary)")
            }
        }
    }

    func testMissingFirstGenerationAndMissingFenceDoNotBecomeFreshAbsence() throws {
        try withScratch { directory in
            let store = makeStore(directory)
            try store.acquireLock()
            let journal = try intendedJournal()
            try store.commitJournal(journal)
            try FileManager.default.removeItem(at: directory.appendingPathComponent("recovery-journal.json"))
            XCTAssertThrowsError(try store.loadJournal())
        }
        try withScratch { directory in
            let store = makeStore(directory)
            try store.acquireLock()
            let journal = try intendedJournal()
            try store.commitJournal(journal)
            try store.commitFence(pendingFence(journal))
            try FileManager.default.removeItem(at: directory.appendingPathComponent("execution-fence.json"))
            XCTAssertThrowsError(try store.loadFence())
        }
    }

    func testLegacyBytesArePreservedAndSymlinkAndUnsafeDirectoryAreRefused() throws {
        try withScratch { directory in
            let store = makeStore(directory)
            try store.acquireLock()
            let legacy = directory.appendingPathComponent("original-pmset.json")
            let bytes = Data("unmodified legacy evidence".utf8)
            try writeFixture(bytes, to: legacy)
            XCTAssertEqual(try store.loadLegacyEvidence(), bytes)
            try FileManager.default.removeItem(at: legacy)
            try FileManager.default.createSymbolicLink(at: legacy, withDestinationURL: directory.appendingPathComponent("recovery.lock"))
            XCTAssertThrowsError(try store.loadLegacyEvidence())
            XCTAssertTrue(try FileManager.default.attributesOfItem(atPath: legacy.path)[.type] as? FileAttributeType == .typeSymbolicLink)
        }
        try withScratch { directory in
            XCTAssertEqual(chmod(directory.path, 0o755), 0)
            XCTAssertThrowsError(try makeStore(directory).acquireLock())
            let permissions = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber)
            XCTAssertEqual(permissions.intValue, 0o755)
        }
    }

    func testCompletedRenameWithFailedDirectoryBarrierRelaunchesAsPending() throws {
        for boundary in [PersistenceBoundary.directorySync, .directoryFullSync, .directoryClose] {
            try withScratch { directory in
                var armed = false
                var occurrences = 0
                var store: DurableJournal? = makeStore(directory) {
                    if armed && $0 == boundary {
                        occurrences += 1
                        // Previous generation, completion marker, then completed fence.
                        if occurrences == 3 { throw InjectedFailure.persistence }
                    }
                }
                try store!.acquireLock()
                let journal = try intendedJournal()
                let pending = pendingFence(journal)
                try store!.commitJournal(journal)
                try store!.commitFence(pending)
                armed = true
                var completed = pending
                completed.completed = true
                XCTAssertThrowsError(try store!.commitFence(completed), "Boundary \(boundary)")
                let visible = try JSONDecoder().decode(ExecutionFence.self,
                    from: Data(contentsOf: directory.appendingPathComponent("execution-fence.json")))
                XCTAssertTrue(visible.completed, "The regression requires a visible completed rename")
                store = nil

                let relaunched = makeStore(directory)
                try relaunched.acquireLock()
                XCTAssertEqual(try relaunched.loadFence(), pending, "Boundary \(boundary)")
                XCTAssertThrowsError(try relaunched.commitFence(completed), "A marker cannot be cleared by same-boot retry")
            }
        }
    }

    func testCompletionMarkerMustBecomeDurableBeforeCompletedFenceIsWritten() throws {
        try withScratch { directory in
            var armed = false
            var synchronizations = 0
            let store = makeStore(directory) {
                if armed && $0 == .directorySync {
                    synchronizations += 1
                    if synchronizations == 2 { throw InjectedFailure.persistence }
                }
            }
            try store.acquireLock()
            let journal = try intendedJournal()
            let pending = pendingFence(journal)
            try store.commitJournal(journal)
            try store.commitFence(pending)
            var completed = pending
            completed.completed = true
            armed = true
            XCTAssertThrowsError(try store.commitFence(completed))
            let visible = try JSONDecoder().decode(ExecutionFence.self,
                from: Data(contentsOf: directory.appendingPathComponent("execution-fence.json")))
            XCTAssertEqual(visible, pending)
            XCTAssertEqual(try store.loadFence(), pending)
        }
    }

    func testCleanupFailureAfterDurableCompletionKeepsPresentMarkerConservative() throws {
        try withScratch { directory in
            var armed = false
            var store: DurableJournal? = makeStore(directory) {
                if armed && $0 == .completionMarkerRemove { throw InjectedFailure.persistence }
            }
            try store!.acquireLock()
            let journal = try intendedJournal()
            let pending = pendingFence(journal)
            try store!.commitJournal(journal)
            try store!.commitFence(pending)
            var completed = pending
            completed.completed = true
            armed = true
            XCTAssertThrowsError(try store!.commitFence(completed))
            store = nil
            let relaunched = makeStore(directory)
            try relaunched.acquireLock()
            XCTAssertEqual(try relaunched.loadFence(), pending)
        }
    }

    func testCleanupDirectoryFailureCannotHideAnUndurableCompletion() throws {
        try withScratch { directory in
            var armed = false
            var synchronizations = 0
            var store: DurableJournal? = makeStore(directory) {
                if armed && $0 == .directorySync {
                    synchronizations += 1
                    if synchronizations == 4 { throw InjectedFailure.persistence }
                }
            }
            try store!.acquireLock()
            let journal = try intendedJournal()
            let pending = pendingFence(journal)
            try store!.commitJournal(journal)
            try store!.commitFence(pending)
            var completed = pending
            completed.completed = true
            armed = true
            XCTAssertThrowsError(try store!.commitFence(completed))
            store = nil
            let relaunched = makeStore(directory)
            try relaunched.acquireLock()
            // The fourth sync is cleanup after the completed fence passed all its barriers.
            XCTAssertEqual(try relaunched.loadFence(), completed)
        }
    }

    func testOldBootMarkerIsRetainedUntilNewCompletionWithoutCompletingOldRequest() throws {
        try withScratch { directory in
            var armed = false
            let store = makeStore(directory) {
                if armed && $0 == .completionMarkerRemove { throw InjectedFailure.persistence }
            }
            try store.acquireLock()
            var journal = try intendedJournal()
            let oldPending = pendingFence(journal)
            try store.commitJournal(journal)
            try store.commitFence(oldPending)
            var completed = oldPending
            completed.completed = true
            armed = true
            XCTAssertThrowsError(try store.commitFence(completed))
            armed = false
            journal.operation = RecoveryOperation(id: UUID(), bootID: laterBoot, kind: .restore,
                preState: [CellValue(cell: cell, value: 0)],
                steps: [RecoveryStep(cell: cell, precondition: 0, target: 1, phase: .intended)])
            journal.revision += 1
            try store.commitJournal(journal)
            let next = pendingFence(journal, bootID: laterBoot, target: 1)
            try store.commitFence(next)
            XCTAssertEqual(try store.loadFence(), next)
            let retained = try JSONDecoder().decode(ExecutionFence.self,
                from: Data(contentsOf: directory.appendingPathComponent("execution-completion-pending.json")))
            XCTAssertEqual(retained, oldPending)
            completed = next
            completed.completed = true
            try store.commitFence(completed)
            XCTAssertEqual(try store.loadFence(), completed)
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("execution-completion-pending.json").path))
        }
    }

    func testPendingFenceRetryRepeatsDurabilityChecksBeforeAdmission() throws {
        try withScratch { directory in
            var armed = false
            let store = makeStore(directory) {
                if armed && $0 == .directorySync { throw InjectedFailure.persistence }
            }
            try store.acquireLock()
            let journal = try intendedJournal()
            let pending = pendingFence(journal)
            try store.commitJournal(journal)
            try store.commitFence(pending)
            armed = true
            XCTAssertThrowsError(try store.commitFence(pending))
            XCTAssertEqual(try store.loadFence(), pending)
        }
    }

    func testSameBootUnknownRequestCannotBeReplacedByAnotherRequest() throws {
        try withScratch { directory in
            let store = makeStore(directory)
            try store.acquireLock()
            var journal = try intendedJournal()
            try store.commitJournal(journal)
            let original = pendingFence(journal)
            try store.commitFence(original)
            journal.operation = RecoveryOperation(id: UUID(), bootID: boot, kind: .restore,
                preState: [CellValue(cell: cell, value: 0)],
                steps: [RecoveryStep(cell: cell, precondition: 0, target: 1, phase: .intended)])
            journal.revision += 1
            try store.commitJournal(journal)
            XCTAssertThrowsError(try store.commitFence(pendingFence(journal, target: 1)))
            XCTAssertEqual(try store.loadFence(), original)
        }
    }

    func testCompletionMarkerAloneAndMalformedMarkerNeverPermitFreshOff() throws {
        try withScratch { directory in
            let store = makeStore(directory)
            try store.acquireLock()
            let pending = pendingFence(try intendedJournal())
            let path = directory.appendingPathComponent("execution-completion-pending.json")
            try writeFixture(JSONEncoder().encode(pending), to: path)
            XCTAssertThrowsError(try store.loadJournal())
            XCTAssertThrowsError(try store.loadFence())
            try writeFixture(Data("corrupt marker".utf8), to: path)
            XCTAssertThrowsError(try store.loadJournal())
            XCTAssertThrowsError(try store.loadFence())
        }
    }

    private func initialJournal() throws -> RecoveryJournal {
        let capture = try ProfileSnapshot(parsing: "AC Power:\n powernap 1\n")
        return RecoveryJournal(uid: getuid(), hostID: host, sessionID: UUID(), revision: 1,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000), capture: capture,
            selectedSettings: ["disablePowerNap"], profiles: [.ac], cells: [RecoveryCell(cell: cell, original: 1)])
    }

    private func intendedJournal() throws -> RecoveryJournal {
        var journal = try initialJournal()
        journal.operation = RecoveryOperation(id: UUID(), bootID: boot, kind: .apply,
            preState: [CellValue(cell: cell, value: 1)],
            steps: [RecoveryStep(cell: cell, precondition: 1, target: 0, phase: .intended)])
        return journal
    }

    private func pendingFence(_ journal: RecoveryJournal, bootID: String? = nil, target: Int = 0) -> ExecutionFence {
        ExecutionFence(uid: getuid(), hostID: host, bootID: bootID ?? boot, incarnationID: UUID(),
            sessionID: journal.sessionID, operationID: journal.operation!.id, cell: cell, target: target, completed: false)
    }

    private func makeStore(_ directory: URL,
                           beforeBoundary: @escaping (PersistenceBoundary) throws -> Void = { _ in }) -> DurableJournal {
        DurableJournal(directory: directory, uid: getuid(), hostID: host, beforeBoundary: beforeBoundary)
    }

    private func withScratch(_ body: (URL) throws -> Void) throws {
        let directory = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("benzo-storage-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    private func writeFixture(_ data: Data, to url: URL) throws {
        try data.write(to: url)
        guard chmod(url.path, 0o600) == 0 else { throw InjectedFailure.persistence }
    }

    private func readJournalFile(_ directory: URL, name: String) throws -> RecoveryJournal {
        try JSONDecoder().decode(RecoveryJournal.self, from: Data(contentsOf: directory.appendingPathComponent(name)))
    }

    private enum InjectedFailure: Error { case persistence }
}
