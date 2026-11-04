import Foundation
import XCTest

final class PermissionObservationTests: XCTestCase {
    func testOrdinaryExistingRuleIsOnlyPresence() {
        var paths: [String] = []
        let observer = PermissionObserver(ruleURL: URL(fileURLWithPath: "/scratch/rule")) { path in
            paths.append(path)
            return [.type: path == "/scratch/rule" ? FileAttributeType.typeRegular : .typeDirectory]
        }

        XCTAssertEqual(observer.observe(), .legacyRulePresent)
        XCTAssertEqual(paths, ["/", "/scratch", "/scratch/rule"])
    }

    func testConfirmedMissingRuleOrAncestorIsAbsent() {
        for missingPath in ["/scratch", "/scratch/rule"] {
            var paths: [String] = []
            let observer = PermissionObserver(ruleURL: URL(fileURLWithPath: "/scratch/rule")) { path in
                paths.append(path)
                if path == missingPath { throw POSIXError(.ENOENT) }
                return [.type: FileAttributeType.typeDirectory]
            }

            XCTAssertEqual(observer.observe(), .noLegacyRule)
            XCTAssertEqual(paths.last, missingPath)
        }
    }

    func testUnreadableOrAmbiguousMetadataIsUnknown() {
        let failures: [Error] = [
            POSIXError(.EACCES),
            POSIXError(.ENOTDIR),
            NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError),
            NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError,
                    userInfo: [NSUnderlyingErrorKey: POSIXError(.EACCES)])
        ]
        for failure in failures {
            let observer = PermissionObserver(ruleURL: URL(fileURLWithPath: "/scratch/rule")) { path in
                if path == "/scratch/rule" { throw failure }
                return [.type: FileAttributeType.typeDirectory]
            }

            guard case .unknown = observer.observe() else {
                return XCTFail("Unconfirmed metadata must not imply absence or presence")
            }
        }
    }

    func testNonregularRuleOrSubstitutedAncestorIsUnknownWithoutFollowingIt() {
        for unexpectedPath in ["/scratch", "/scratch/rule"] {
            for type in [FileAttributeType.typeSymbolicLink, .typeSocket, .typeUnknown] {
                var paths: [String] = []
                let observer = PermissionObserver(ruleURL: URL(fileURLWithPath: "/scratch/rule")) { path in
                    paths.append(path)
                    return [.type: path == unexpectedPath ? type : FileAttributeType.typeDirectory]
                }

                guard case .unknown = observer.observe() else {
                    return XCTFail("Substituted metadata must remain unknown")
                }
                XCTAssertEqual(paths.last, unexpectedPath)
            }
        }
    }

    func testMissingTypeOrInvalidURLIsUnknown() {
        let missingType = PermissionObserver(ruleURL: URL(fileURLWithPath: "/scratch/rule")) { _ in [:] }
        guard case .unknown = missingType.observe() else {
            return XCTFail("Missing metadata type must remain unknown")
        }
        var calls = 0
        let invalid = PermissionObserver(ruleURL: URL(string: "https://example.invalid/rule")!) { _ in
            calls += 1
            return [.type: FileAttributeType.typeRegular]
        }
        guard case .unknown = invalid.observe() else {
            return XCTFail("A nonlocal path must remain unknown")
        }
        XCTAssertEqual(calls, 0)
    }

    func testScratchRuleAndOriginalsRemainUnchanged() throws {
        let directory = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let rule = directory.appendingPathComponent("legacy-rule")
        let originals = directory.appendingPathComponent("originals.json")
        let ruleBytes = Data("preserve even invalid rule contents".utf8)
        let originalBytes = Data("preserve original settings evidence".utf8)
        try ruleBytes.write(to: rule)
        try originalBytes.write(to: originals)
        let observer = PermissionObserver(ruleURL: rule, metadata: scratchMetadata)

        XCTAssertEqual(observer.observe(), .legacyRulePresent)
        XCTAssertEqual(try Data(contentsOf: rule), ruleBytes)
        XCTAssertEqual(try Data(contentsOf: originals), originalBytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(),
                       ["legacy-rule", "originals.json"])
    }

    func testScratchMissingDirectoriesRemainUncreated() {
        let directory = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let observer = PermissionObserver(ruleURL: directory.appendingPathComponent("nested/rule"),
                                          metadata: scratchMetadata)

        XCTAssertEqual(observer.observe(), .noLegacyRule)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testScratchLeafAndAncestorSymlinksAndDirectoryRemainUnknownAndUnchanged() throws {
        let directory = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("missing")
        let link = directory.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        for rule in [link, link.appendingPathComponent("nested/rule"), directory] {
            let observer = PermissionObserver(ruleURL: rule, metadata: scratchMetadata)
            guard case .unknown = observer.observe() else {
                return XCTFail("A substituted leaf or ancestor must not count as confirmed absence")
            }
        }
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), target.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }

    private func scratchMetadata(_ path: String) throws -> [FileAttributeKey: Any] {
        try FileManager.default.attributesOfItem(atPath: path)
    }
}
