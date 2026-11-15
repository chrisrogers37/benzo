import Foundation
import XCTest

final class CommandRunnerTests: XCTestCase {
    // The engine budget includes cleanup. This allowance covers CI scheduling,
    // not extra engine waits; fixture children also self-expire after five seconds.
    private let schedulingTolerance: TimeInterval = 2

    func testFixedReadRequestsHaveOnlyTheThreeDiagnosticMappings() {
        let requests = ReadCommand.allCases.map(\.request)
        XCTAssertEqual(requests.map(\.executable), ["/usr/bin/pmset", "/usr/bin/pmset", "/usr/sbin/system_profiler"])
        XCTAssertEqual(requests.map(\.arguments), [["-g"], ["-g", "log"], ["SPUSBDataType", "-json"]])
        XCTAssertEqual(requests.map(\.timeout), [10, 10, 30])
        XCTAssertEqual(requests.map(\.maximumOutputBytes), [8, 8, 16].map { $0 * 1_024 * 1_024 })
        XCTAssertEqual(requests.map(\.finalizationReserve), [0.5, 0.5, 0.5])
    }

    func testDrainsMoreThanOneMiBFromEachStreamWithoutDeadlock() async throws {
        let result = await CommandRunner().run(request: try request("streams"))

        XCTAssertEqual(result.termination, .exited(0))
        XCTAssertEqual(result.stdout.count, 2 * 1_024 * 1_024 + 7)
        XCTAssertEqual(result.stderr.count, 2 * 1_024 * 1_024 + 7)
        XCTAssertEqual(result.stdout.prefix(7), Data("stdout\n".utf8))
        XCTAssertEqual(result.stderr.prefix(7), Data("stderr\n".utf8))
        XCTAssertTrue(result.outputComplete)
        XCTAssertFalse(result.outputTruncated)
        XCTAssertTrue(result.directChildStopped)
        XCTAssertTrue(result.isSuccess)
    }

    func testCombinedCapDiscardsExcessWhileDrainingToEOF() async throws {
        let cap = 128 * 1_024
        let result = await CommandRunner().run(request: try request("streams", maximumOutputBytes: cap))

        XCTAssertEqual(result.termination, .exited(0))
        XCTAssertEqual(result.stdout.count + result.stderr.count, cap)
        XCTAssertTrue(result.outputComplete)
        XCTAssertTrue(result.outputTruncated)
        XCTAssertTrue(result.directChildStopped)
        XCTAssertFalse(result.isSuccess)
    }

    func testNonzeroExitRetainsSeparateStderrEvidence() async throws {
        // Exactly filling the combined cap must not be reported as truncation.
        let result = await CommandRunner().run(request: try request("nonzero", maximumOutputBytes: 19))

        XCTAssertEqual(result.termination, .exited(23))
        XCTAssertEqual(result.stdout, Data("out\n".utf8))
        XCTAssertEqual(result.stderr, Data("failure detail\n".utf8))
        XCTAssertTrue(result.outputComplete)
        XCTAssertFalse(result.outputTruncated)
        XCTAssertFalse(result.isSuccess)
    }

    func testSignalIsNotAnExitCodeOrCancellation() async throws {
        let result = await CommandRunner().run(request: try request("signal"))

        XCTAssertEqual(result.termination, .signaled(SIGTERM))
        XCTAssertEqual(result.stderr, Data("signal detail\n".utf8))
        XCTAssertTrue(result.outputComplete)
        XCTAssertTrue(result.directChildStopped)
        XCTAssertFalse(result.isSuccess)
    }

    func testMissingExecutableReturnsLaunchFailure() async {
        let request = CommandRequest(executable: "/nonexistent-benzo-fixture-\(UUID().uuidString)", arguments: [], timeout: 2, maximumOutputBytes: 1_024)
        let result = await CommandRunner().run(request: request)

        guard case .launchFailed(let detail) = result.termination else { return XCTFail("Expected launch failure") }
        XCTAssertFalse(detail.isEmpty)
        XCTAssertTrue(result.stdout.isEmpty)
        XCTAssertTrue(result.stderr.isEmpty)
        XCTAssertFalse(result.outputComplete)
        XCTAssertTrue(result.directChildStopped)
        XCTAssertFalse(result.isSuccess)
    }

    func testTimeoutStopsOnlyTheOwnedDirectChildWithinTotalBudget() async throws {
        let scratch = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let request = try request("hang", scratch: scratch, timeout: 1)
        let start = ProcessInfo.processInfo.systemUptime
        let result = await CommandRunner().run(request: request)

        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, request.timeout + schedulingTolerance)
        XCTAssertEqual(result.termination, .timedOut)
        XCTAssertEqual(result.stdout, Data("ready\n".utf8))
        XCTAssertTrue(result.directChildStopped)
        XCTAssertFalse(result.outputComplete)
        XCTAssertFalse(result.isSuccess)
    }

    func testCancellationStopsOwnedDirectChildWithinCleanupReserve() async throws {
        let scratch = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let request = try request("hang", scratch: scratch)
        let task = Task { await CommandRunner().run(request: request) }
        let ready = await waitForFile("ready", in: scratch)
        let start = ProcessInfo.processInfo.systemUptime
        task.cancel()
        let result = await task.value

        XCTAssertTrue(ready)
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, request.finalizationReserve + schedulingTolerance)
        XCTAssertEqual(result.termination, .cancelled)
        XCTAssertEqual(result.stdout, Data("ready\n".utf8))
        XCTAssertTrue(result.directChildStopped)
        XCTAssertFalse(result.outputComplete)
        XCTAssertFalse(result.isSuccess)
    }

    func testAlreadyCancelledTaskDoesNotLaunchItsFixture() async throws {
        let scratch = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let request = try request("hang", scratch: scratch)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await CommandRunner().run(request: request)
        }
        let result = await task.value

        XCTAssertEqual(result.termination, .cancelled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: scratch.appendingPathComponent("ready").path))
        XCTAssertTrue(result.stdout.isEmpty)
        XCTAssertTrue(result.stderr.isEmpty)
        XCTAssertTrue(result.directChildStopped)
        XCTAssertFalse(result.outputComplete)
        XCTAssertFalse(result.isSuccess)
    }

    func testExitedChildWithInheritedWritersCannotHoldReturnOpen() async throws {
        let scratch = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let request = try request("inherited-writer", scratch: scratch, timeout: 1)
        let start = ProcessInfo.processInfo.systemUptime
        let result = await CommandRunner().run(request: request)
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        let descendantStillWaiting = !FileManager.default.fileExists(atPath: scratch.appendingPathComponent("done").path)
        let cleanedUp = await finishFixture(in: scratch)

        XCTAssertLessThan(elapsed, request.timeout + schedulingTolerance)
        XCTAssertEqual(result.termination, .timedOut)
        XCTAssertTrue(result.directChildStopped)
        XCTAssertTrue(descendantStillWaiting, "Direct-child exit is not descendant quiescence")
        XCTAssertTrue(cleanedUp)
        XCTAssertFalse(result.outputComplete)
        XCTAssertFalse(result.isSuccess)
    }

    func testCancellationAlsoClosesDescendantHeldWriters() async throws {
        let scratch = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let request = try request("inherited-writer", scratch: scratch)
        let task = Task { await CommandRunner().run(request: request) }
        let ready = await waitForFile("ready", in: scratch)
        let start = ProcessInfo.processInfo.systemUptime
        task.cancel()
        let result = await task.value
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        let cleanedUp = await finishFixture(in: scratch)

        XCTAssertTrue(ready)
        XCTAssertLessThan(elapsed, request.finalizationReserve + schedulingTolerance)
        XCTAssertEqual(result.termination, .cancelled)
        XCTAssertTrue(result.directChildStopped)
        XCTAssertTrue(cleanedUp)
        XCTAssertFalse(result.outputComplete)
        XCTAssertFalse(result.isSuccess)
    }

    func testUnstoppedDirectChildIsReportedWithoutUnboundedWait() async throws {
        let scratch = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let request = try request("ignore-term", scratch: scratch, timeout: 1)
        let start = ProcessInfo.processInfo.systemUptime
        let result = await CommandRunner().run(request: request)
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        let cleanedUp = await finishFixture(in: scratch)

        XCTAssertLessThan(elapsed, request.timeout + schedulingTolerance)
        XCTAssertEqual(result.termination, .timedOut)
        XCTAssertFalse(result.directChildStopped)
        XCTAssertTrue(cleanedUp)
        XCTAssertFalse(result.outputComplete)
        XCTAssertFalse(result.isSuccess)
    }

    func testBoundedInputIsDeliveredExactlyAndClosed() async throws {
        let fixture = try request("input")
        let payload = Data(repeating: 65, count: 4_096)
        let input = CommandRequest(executable: fixture.executable, arguments: fixture.arguments,
            timeout: 5, maximumOutputBytes: 4_096, standardInput: payload,
            environment: ["PATH": "/usr/bin:/bin"])
        let result = await CommandRunner().run(request: input)
        XCTAssertTrue(result.isSuccess)
        XCTAssertTrue(result.directChildStopped)
        XCTAssertEqual(result.stdout, payload)
        XCTAssertEqual(result.stderr, Data())
    }

    private func request(_ mode: String, scratch: URL? = nil, timeout: TimeInterval = 5, maximumOutputBytes: Int = 8 * 1_024 * 1_024) throws -> CommandRequest {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "owned-read-child", withExtension: "sh"))
        return CommandRequest(executable: "/bin/sh", arguments: [fixture.path, mode] + (scratch.map { [$0.path] } ?? []), timeout: timeout, maximumOutputBytes: maximumOutputBytes, finalizationReserve: 0.25)
    }

    private func scratchDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("benzo-read-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func waitForFile(_ name: String, in directory: URL) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + 6
        while ProcessInfo.processInfo.systemUptime < deadline {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path) { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return false
    }

    private func finishFixture(in directory: URL) async -> Bool {
        do { try Data().write(to: directory.appendingPathComponent("stop")) }
        catch { return false }
        return await waitForFile("done", in: directory)
    }
}
