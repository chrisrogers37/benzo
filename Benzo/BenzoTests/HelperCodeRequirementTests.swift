import Foundation
import Security
import XCTest

final class HelperCodeRequirementTests: XCTestCase {
    func testBothPeersRequireExactDeveloperIDTeamIdentityAndVersionedSignedRole() throws {
        for (identifier, role) in [("com.benzo.app", "client-v1"), ("com.benzo.helper", "service-v1")] {
            let actual = try HelperCodeRequirement.requirement(for: identifier, teamIdentifier: "AB12CD34EF")
            // Compare parsed requirements, including the entire conjunction, so
            // adding an alternative or dropping a restriction fails this test.
            let expected = """
            anchor apple generic
            and certificate 1[field.1.2.840.113635.100.6.2.6] exists
            and certificate leaf[field.1.2.840.113635.100.6.1.13] exists
            and certificate leaf[subject.OU] = "AB12CD34EF"
            and identifier "\(identifier)"
            and info[BenzoHelperRole] = "\(role)"
            and ! entitlement["com.apple.security.get-task-allow"] exists
            and ! entitlement["com.apple.security.cs.disable-library-validation"] exists
            and ! entitlement["com.apple.security.cs.allow-dyld-environment-variables"] exists
            """
            XCTAssertEqual(try compiled(actual), try compiled(expected))
        }
    }

    func testPeerAndTeamChangesProduceDifferentRequirements() throws {
        let app = try compiled(HelperCodeRequirement.requirement(for: "com.benzo.app", teamIdentifier: "AB12CD34EF"))
        let helper = try compiled(HelperCodeRequirement.requirement(for: "com.benzo.helper", teamIdentifier: "AB12CD34EF"))
        let otherTeam = try compiled(HelperCodeRequirement.requirement(for: "com.benzo.app", teamIdentifier: "ZX98WV76UT"))
        XCTAssertNotEqual(app, helper)
        XCTAssertNotEqual(app, otherTeam)
    }

    func testRejectsUnknownIdentifiersAndRequirementInjection() {
        for identifier in ["", "com.benzo.app.old", "com.benzo.helper.other", "COM.BENZO.APP", "com.benzo.app\" or true"] {
            XCTAssertThrowsError(try HelperCodeRequirement.requirement(for: identifier, teamIdentifier: "AB12CD34EF"))
        }
        for team in ["", "AB12CD34E", "AB12CD34EF0", "ab12cd34ef", "AB12CD34E\n", "AB12CD34É", "\" or true "] {
            XCTAssertThrowsError(try HelperCodeRequirement.requirement(for: "com.benzo.app", teamIdentifier: team))
        }
    }

    private func compiled(_ source: String) throws -> Data {
        var requirement: SecRequirement?
        let status = SecRequirementCreateWithString(source as CFString, [], &requirement)
        XCTAssertEqual(status, errSecSuccess)
        let parsed = try XCTUnwrap(requirement)
        var rawData: CFData?
        XCTAssertEqual(SecRequirementCopyData(parsed, [], &rawData), errSecSuccess)
        return try XCTUnwrap(rawData) as Data
    }
}
