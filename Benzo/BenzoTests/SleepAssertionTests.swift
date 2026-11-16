import Foundation
import XCTest

@MainActor
final class SleepAssertionTests: XCTestCase {
    func testSupportedMacOSOutputSeparatesSleepDisplayActivityAndKernelEvidence() throws {
        let result = try SleepAssertions.parse(Self.reportedExample).get()
        XCTAssertEqual(result.summary["PreventUserIdleSystemSleep"], 1)
        XCTAssertEqual(result.summary["PreventSystemSleep"], 0)
        XCTAssertEqual(result.processes.count, 4)
        let app = try XCTUnwrap(result.processes.first { $0.pid == 631 })
        XCTAssertEqual(app.processName, "Example Awake")
        XCTAssertEqual(app.assertions.map(\.category), [.idleSleep, .displaySleep])
        XCTAssertEqual(app.assertions.map(\.name), ["Keep a download running", "Presentation display"])
        XCTAssertEqual(app.assertions[0].details, ["Timeout will fire in 120 secs Action=TimeoutActionTurnOff"])
        let electron = try XCTUnwrap(result.processes.first { $0.pid == 842 })
        XCTAssertEqual(electron.assertions.first?.category, .idleSleep)
        XCTAssertEqual(result.processes.first { $0.processName == "WindowServer" }?.assertions.first?.category, .other)
        XCTAssertEqual(result.kernelSummary, "USB,THNDR")
        XCTAssertEqual(result.kernelDetails.count, 2)
        XCTAssertEqual(result.sleepPreventers, ["Idle sleep preventers: IODisplayWrangler"])
    }

    func testSuccessfulEmptyRequiresSupportedSummaryOwnersAndKernelFooter() throws {
        let empty = try SleepAssertions.parse(Self.empty).get()
        XCTAssertTrue(empty.processes.isEmpty)
        XCTAssertNil(empty.kernelSummary)
        XCTAssertTrue(empty.kernelDetails.isEmpty)
        XCTAssertTrue(empty.sleepPreventers.isEmpty)
        // IOPMCopyAssertionsByProcess can return an empty dictionary, which pmset
        // renders without the literal None; its following kernel footer is required.
        XCTAssertTrue(try SleepAssertions.parse(Self.empty.replacingOccurrences(of: "   None\n", with: "")).get().processes.isEmpty)
    }

    func testSystemSleepIsDistinctFromIdleAndDisplayAliases() throws {
        let output = Self.empty.replacingOccurrences(of: "PreventSystemSleep             0", with: "PreventSystemSleep             1")
            .replacingOccurrences(of: "   None", with: """
               pid 91(backupd): [0x0000000000000041] 00:00:08 PreventSystemSleep named: "Finishing backup"
               pid 92(Presentation): [0x0000000000000042] 00:00:08 NoDisplaySleepAssertion named: "Slides"
            """)
        let result = try SleepAssertions.parse(output).get()
        XCTAssertEqual(result.processes[0].assertions[0].category, .systemSleep)
        XCTAssertEqual(result.processes[1].assertions[0].category, .displaySleep)
    }

    func testIdentityUsesPIDAndReportedNameAndRetainsMultipleAssertionIDs() throws {
        let rows = """
           pid 11(Worker): [0x0000000000000011] 00:00:01 PreventUserIdleSystemSleep named: "First"
           pid 12(Worker): [0x0000000000000012] 00:00:01 PreventUserIdleSystemSleep named: "First"
           pid 11(Worker): [0x0000000000000013] 00:00:01 PreventUserIdleSystemSleep named: "First"
           pid 11(Different): [0x0000000000000014] 00:00:01 PreventUserIdleSystemSleep named: "Second"
        """
        let result = try SleepAssertions.parse(Self.empty.replacingOccurrences(of: "   None", with: rows)).get()
        XCTAssertEqual(result.processes.count, 3)
        XCTAssertEqual(Set(result.processes.map(\.id)).count, 3)
        XCTAssertEqual(result.processes[0].assertions.map(\.id), ["0x0000000000000011", "0x0000000000000013"])
    }

    func testFriendlyNamesNeverMergeDistinctReportedProcesses() throws {
        let rows = """
           pid 11(powerd): [0x0000000000000011] PreventUserIdleSystemSleep named: "Display on"
           pid 11(Power Management): [0x0000000000000012] PreventUserIdleSystemSleep named: "Other process"
        """
        let result = try SleepAssertions.parse(Self.empty.replacingOccurrences(of: "   None", with: rows)).get()
        XCTAssertEqual(result.processes.map(\.displayName), ["Power Management", "Power Management"])
        XCTAssertNotEqual(result.processes[0].id, result.processes[1].id)
    }

    func testExactDuplicateRowsCoalesceButConflictingIDsFail() throws {
        let row = "pid 11(Worker): [0x0000000000000011] 00:00:01 PreventUserIdleSystemSleep named: \"First\"\n\tDetails: Downloading"
        let duplicated = Self.empty.replacingOccurrences(of: "   None", with: row + "\n" + row)
        XCTAssertEqual(try SleepAssertions.parse(duplicated).get().processes[0].assertions.count, 1)
        assertFailure(Self.empty.replacingOccurrences(of: "   None", with: row + "\n" + row.replacingOccurrences(of: "First", with: "Different")))
    }

    func testUnknownTypesAreRetainedAsOtherAndSuspensionIsNotActive() throws {
        let output = Self.empty.replacingOccurrences(of: "   None", with: """
           pid 61(service): [0x0000000000000061] 00:00:01 NewAssertionType named: "Future behavior"
           pid 61(service): [0x0000000000000062] 00:00:01 PreventUserIdleSystemSleep named: "Suspended task" (Suspended)
           pid 62(logger): [0x0000000000000063] 00:00:01 PreventUserIdleSystemSleep named: "Logged timeout" (timed out)
        """)
        let result = try SleepAssertions.parse(output).get()
        XCTAssertEqual(result.processes[0].assertions[0].type, "NewAssertionType")
        XCTAssertEqual(result.processes[0].assertions[0].category, .other)
        XCTAssertFalse(result.processes[0].assertions[1].isActive)
        XCTAssertTrue(result.processes[1].assertions[0].isTimedOut)
        XCTAssertTrue(result.processes[1].assertions[0].isActive, "A log-only timeout does not release the assertion")
    }

    func testSupportedOptionalDetailsRemainAttachedToTheirAssertion() throws {
        let output = Self.empty.replacingOccurrences(of: "   None", with: """
           pid 73(service helper): [0x0000000000000073] PreventUserIdleSystemSleep named: "An \\"embedded\\" quote"
            Details: Keeping a transfer running
            Created for PID: 74. Description: Other application
            Resources: Network
            Localized=Transfer in progress
            Assertion applied on AC  power only
            Timeout will fire in 30 secs Action=<unknown action>
        """)
        let assertion = try SleepAssertions.parse(output).get().processes[0].assertions[0]
        XCTAssertEqual(assertion.details.count, 6)
        XCTAssertTrue(assertion.name.contains("embedded"))
    }

    func testIncompleteMalformedAndUnrecognizedOutputsNeverBecomeEmpty() {
        let invalid = [
            "", "unrecognized output", "Assertion status system-wide:",
            Self.empty.replacingOccurrences(of: "Listed by owning process:", with: "Process information unavailable:"),
            Self.empty.replacingOccurrences(of: "No kernel assertions.", with: ""),
            Self.empty.replacingOccurrences(of: "No kernel assertions.", with: "Kernel Assertions: 0x4=USB"),
            Self.empty.replacingOccurrences(of: "   None", with: "pid 11(Worker): [0x11] 00:00:01 PreventUserIdleSystemSleep named: \"unfinished"),
            Self.empty.replacingOccurrences(of: "   None", with: "pid 11(Worker): [0x11] nonsense"),
            Self.empty.replacingOccurrences(of: "   None", with: "Details: orphaned detail"),
            Self.empty.replacingOccurrences(of: "PreventSystemSleep             0", with: "PreventSystemSleep             invalid"),
            Self.empty.replacingOccurrences(of: "PreventSystemSleep             0", with: "PreventSystemSleep             0\n   PreventSystemSleep 1"),
            Self.empty.replacingOccurrences(of: "PreventSystemSleep             0", with: ""),
            Self.empty + "\nIdle sleep preventers: incomplete...",
            Self.empty + "\nnew output section",
        ]
        invalid.forEach { assertFailure($0) }
    }

    func testActiveSummaryWithoutCorrespondingOwnersFailsIncludingSuspendedOnly() {
        for key in ["PreventUserIdleSystemSleep", "PreventSystemSleep", "PreventUserIdleDisplaySleep", "UserIsActive", "ExternalMedia", "BackgroundTask"] {
            let lines = Self.empty.components(separatedBy: .newlines).map { line in
                line.trimmingCharacters(in: .whitespaces).hasPrefix(key + " ") ? "   \(key) 1" : line
            }
            let output = lines.joined(separator: "\n")
            assertFailure(output)
            assertFailure(output.replacingOccurrences(of: "   None", with: "pid 1(service): [0x11] \(key) named: \"Paused\" (Suspended)"))
        }
    }

    func testIndependentDatasetsDoNotCarryProcessOrKernelHistory() throws {
        let first = try SleepAssertions.parse(Self.reportedExample).get()
        let second = try SleepAssertions.parse(Self.empty).get()
        XCTAssertFalse(first.processes.isEmpty)
        XCTAssertTrue(second.processes.isEmpty)
        XCTAssertNil(second.kernelSummary)
    }

    func testMixedEncodingDecodesOnlyMacRomanFieldsAndPreservesUTF8Identity() throws {
        let result = try SleepAssertions.parse(Self.mixedEncodingReport()).get()
        let process = try XCTUnwrap(result.processes.first)
        XCTAssertEqual(process.processName, "Résumé")
        XCTAssertEqual(process.id, "67:Résumé")
        XCTAssertEqual(process.assertions[0].name, "Café")
        XCTAssertEqual(process.assertions[0].details, [
            "Details: Café transfer", "Resources: Réseau",
            "Created for PID: 68. Description: Café task", "Localized=Téléchargement à venir",
        ])
        XCTAssertEqual(result.kernelDetails, ["id=9 level=255 0x4=USB description=Station été owner=Écran USB"])
        XCTAssertEqual(result.sleepPreventers, ["Idle sleep preventers: Écran"])
    }

    func testMacRomanFieldsDoNotPreferCoincidentallyValidUTF8Bytes() throws {
        // C3 A9 is “é” in UTF-8 but “√©” in the assertion field's source encoding.
        let result = try SleepAssertions.parse(Self.mixedEncodingReport(assertionName: Data([0xc3, 0xa9]))).get()
        XCTAssertEqual(result.processes[0].assertions[0].name, "√©")
        XCTAssertEqual(result.processes[0].processName, "Résumé")
        let highByte = try SleepAssertions.parse(Self.mixedEncodingReport(assertionName: Data([0x85]))).get()
        XCTAssertEqual(highByte.processes[0].assertions[0].name, "Ö", "MacRoman 85 must not be interpreted as a newline")
    }

    func testMixedEncodingRejectsInvalidProcessStructuralLocalizedAndKernelUTF8() throws {
        var invalidReports = [Self.mixedEncodingReport(processName: Data([0x52, 0xff]))]
        for target in ["Assertion status system-wide:", "Localized=Téléchargement à venir", "owner=Écran USB"] {
            var invalid = Self.mixedEncodingReport()
            let range = try XCTUnwrap(invalid.range(of: Data(target.utf8)))
            var bytes = Data(target.utf8)
            bytes.append(0xff)
            invalid.replaceSubrange(range, with: bytes)
            invalidReports.append(invalid)
        }
        var invalidEmpty = Data(Self.empty.utf8)
        invalidEmpty.append(contentsOf: [0x0a, 0xff])
        invalidReports.append(invalidEmpty)
        for bytes in invalidReports {
            guard case .failure = SleepAssertions.parse(bytes) else {
                return XCTFail("Bytes outside known MacRoman fields must not get a fallback decoder")
            }
        }
    }

    func testAssertionReaderAcceptsMixedEncodingCompleteOutput() async throws {
        let reader = FakeReadCommandRunner()
        reader.outcome = CommandOutcome(stdout: Self.mixedEncodingReport(), stderr: Data(), termination: .exited(0),
                                        outputComplete: true, outputTruncated: false, directChildStopped: true)
        let result = try await DiagnosticService(reader: reader).fetchSleepAssertions().get()
        XCTAssertEqual(result.processes[0].processName, "Résumé")
        XCTAssertEqual(result.processes[0].assertions[0].name, "Café")
    }

    func testAssertionReaderPreservesTransportFailuresAndNeverParsesPartialOutput() async throws {
        let reader = FakeReadCommandRunner()
        let service = DiagnosticService(reader: reader)
        reader.outcome = outcome(Self.empty)
        let empty = try await service.fetchSleepAssertions().get()
        XCTAssertTrue(empty.processes.isEmpty)
        XCTAssertEqual(reader.calls, [.sleepAssertions])
        for termination in [Termination.exited(1), .timedOut, .cancelled, .launchFailed("fixture")] {
            reader.outcome = outcome(Self.empty, termination: termination)
            guard case .failure(.commandFailed) = await service.fetchSleepAssertions() else {
                return XCTFail("A failed command must not publish the parseable stdout")
            }
        }
        for (complete, truncated, stopped) in [(false, false, true), (true, true, true), (true, false, false)] {
            reader.outcome = outcome(Self.empty, complete: complete, truncated: truncated, stopped: stopped)
            guard case .failure = await service.fetchSleepAssertions() else { return XCTFail("Incomplete transport must fail") }
        }
        reader.outcome = outcome(Self.empty, stderr: "pmset warning")
        guard case .failure = await service.fetchSleepAssertions() else { return XCTFail("Diagnostics on stderr must not be silently ignored") }
        reader.outcome = CommandOutcome(stdout: Data([0xff]), stderr: Data(), termination: .exited(0), outputComplete: true, outputTruncated: false, directChildStopped: true)
        guard case .failure(.malformedFormat) = await service.fetchSleepAssertions() else { return XCTFail("Invalid encoding must fail") }
    }

    private func assertFailure(_ output: String, file: StaticString = #filePath, line: UInt = #line) {
        guard case .failure = SleepAssertions.parse(output) else { return XCTFail("Must not accept ambiguous output: \(output)", file: file, line: line) }
    }

    private func outcome(_ output: String, termination: Termination = .exited(0), complete: Bool = true,
                         truncated: Bool = false, stopped: Bool = true, stderr: String = "") -> CommandOutcome {
        CommandOutcome(stdout: Data(output.utf8), stderr: Data(stderr.utf8), termination: termination,
                       outputComplete: complete, outputTruncated: truncated, directChildStopped: stopped)
    }

    // Explicit bytes avoid relying on the decoder under test to construct its
    // oracle: é is 8E in MacRoman, while process/localized/kernel text is UTF-8.
    private static func mixedEncodingReport(processName: Data = Data("Résumé".utf8),
                                            assertionName: Data = Data([0x43, 0x61, 0x66, 0x8e])) -> Data {
        let preamble = empty.components(separatedBy: "   None")[0]
            .replacingOccurrences(of: "PreventUserIdleSystemSleep     0", with: "PreventUserIdleSystemSleep     1")
        var bytes = Data(preamble.utf8)
        func utf8(_ string: String) { bytes.append(contentsOf: string.utf8) }
        utf8("   pid 67(")
        bytes.append(processName)
        utf8("): [0x0000000000000067] 00:00:04 PreventUserIdleSystemSleep named: \"")
        bytes.append(assertionName)
        utf8("\"\n\tDetails: Caf")
        bytes.append(0x8e)
        utf8(" transfer\n\tResources: R")
        bytes.append(0x8e)
        utf8("seau\n\tCreated for PID: 68. Description: Caf")
        bytes.append(0x8e)
        utf8(" task\n\tLocalized=Téléchargement à venir\n")
        utf8("Kernel Assertions: 0x4=USB\n   id=9 level=255 0x4=USB description=Station été owner=Écran USB\n")
        utf8("Idle sleep preventers: Écran\n")
        return bytes
    }

    // Supported pmset grammar, with synthetic identities and descriptions. This is
    // an independent captured-output-shaped fixture, never the host's current truth.
    static let empty = """
    2026-06-03 11:20:31 -0400
    Assertion status system-wide:
       BackgroundTask                 0
       ApplePushServiceTask           0
       UserIsActive                   0
       PreventUserIdleDisplaySleep    0
       SoftwareUpdateTask             0
       PreventSystemSleep             0
       ExternalMedia                  0
       PreventUserIdleSystemSleep     0
       NetworkClientActive            0
    Listed by owning process:
       None
    No kernel assertions.
    """

    static let reportedExample = """
    2026-06-03 11:20:31 -0400
    Assertion status system-wide:
       BackgroundTask                 0
       ApplePushServiceTask           0
       UserIsActive                   1
       PreventUserIdleDisplaySleep    1
       SoftwareUpdateTask             0
       PreventSystemSleep             0
       ExternalMedia                  1
       PreventUserIdleSystemSleep     1
       NetworkClientActive            0
    Listed by owning process:
       pid 842(Example Chat): [0x001e00a8000184a3] 28:46:14 NoIdleSleepAssertion named: "Electron"
       pid 631(Example Awake): [0x00041d3b000196cd] 500:03:23 PreventUserIdleSystemSleep named: "Keep a download running"
        Timeout will fire in 120 secs Action=TimeoutActionTurnOff
       pid 631(Example Awake): [0x00041d3b000596ce] 500:03:23 PreventUserIdleDisplaySleep named: "Presentation display"
       pid 112(powerd): [0x001ba4c30008a21e] 71:42:51 ExternalMedia named: "com.apple.powermanagement.externalmediamounted"
       pid 171(WindowServer): [0x0002e6c900098768] 00:00:01 UserIsActive named: "com.apple.iohideventsystem.queue.tickle"
    Kernel Assertions: 0x24=USB,THNDR
       id=546  level=255 0x20=THNDR creat=  mod= description=acio0 owner=AppleThunderboltHALType5
       id=592  level=255 0x4=USB creat= description=com.apple.usb.externaldevice.01200000 owner=Example Hub
    Idle sleep preventers: IODisplayWrangler
    """
}
