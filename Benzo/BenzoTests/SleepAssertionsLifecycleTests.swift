import Foundation
import XCTest

@MainActor
final class SleepAssertionsLifecycleTests: XCTestCase {
    private final class Reads {
        var pending: [CheckedContinuation<Result<SleepAssertions, DiagnosticReadError>, Never>] = []
        var calls = 0
        var cancellations = 0
        func read() async -> Result<SleepAssertions, DiagnosticReadError> {
            calls += 1
            let result = await withCheckedContinuation { pending.append($0) }
            if Task.isCancelled { cancellations += 1 }
            return result
        }
        func finish(_ value: Result<SleepAssertions, DiagnosticReadError>) { pending.removeFirst().resume(returning: value) }
    }

    private final class Delays {
        var pending: [CheckedContinuation<Void, Error>] = []
        var seconds: [TimeInterval] = []
        var cancellations = 0
        func wait(_ seconds: TimeInterval) async throws {
            self.seconds.append(seconds)
            try await withCheckedThrowingContinuation { pending.append($0) }
            if Task.isCancelled { cancellations += 1 }
        }
        func finish() { pending.removeFirst().resume() }
        func finishAll() { while !pending.isEmpty { finish() } }
    }

    private func snapshot(_ name: String? = nil) -> SleepAssertions {
        SleepAssertions(summary: ["PreventSystemSleep": 0, "PreventUserIdleSystemSleep": name == nil ? 0 : 1],
            processes: name.map { [SleepAssertionProcess(pid: 41, processName: $0, assertions: [
                SleepAssertion(id: "0x1", type: "PreventUserIdleSystemSleep", name: "Working", details: [], isSuspended: false, isTimedOut: false)
            ])] } ?? [], kernelSummary: nil, kernelDetails: [], sleepPreventers: [])
    }

    private func settle(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<1000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Async fixture did not settle", file: file, line: line)
    }

    func testOnlyVisibleDiagnosticsPollsAndEmptyIsSuccessful() async {
        let reads = Reads(), delays = Delays()
        let date = Date(timeIntervalSince1970: 1234)
        let model = SleepAssertionsViewModel(read: reads.read, now: { date }, wait: delays.wait)
        model.refresh()
        model.setDiagnosticsVisible(true)
        XCTAssertEqual(reads.calls, 0)
        model.setPopoverVisible(true)
        await settle { reads.calls == 1 }
        XCTAssertEqual(model.status, .loading)
        model.refresh()
        model.setPopoverVisible(true)
        XCTAssertEqual(reads.calls, 1)
        reads.finish(.success(snapshot()))
        await settle { !delays.pending.isEmpty }
        XCTAssertEqual(model.status, .success)
        XCTAssertEqual(model.observation?.value.processes, [])
        XCTAssertEqual(model.observation?.updatedAt, date)
        XCTAssertEqual(delays.seconds, [5])
        delays.finish()
        await settle { reads.calls == 2 }
        model.setDiagnosticsVisible(false)
        reads.finish(.success(snapshot("Late")))
        await settle { reads.cancellations == 1 }
        XCTAssertEqual(model.status, .idle)
        XCTAssertNil(model.observation)
        XCTAssertTrue(delays.pending.isEmpty)
    }

    func testCloseAndRapidReopenRejectOldResultWithoutOverlappingReads() async {
        let reads = Reads(), delays = Delays()
        let model = SleepAssertionsViewModel(read: reads.read, now: Date.init, wait: delays.wait)
        model.setPopoverVisible(true)
        model.setDiagnosticsVisible(true)
        await settle { reads.calls == 1 }
        model.setPopoverVisible(false)
        model.setPopoverVisible(true)
        model.refresh()
        XCTAssertEqual(reads.calls, 1)
        reads.finish(.success(snapshot("Old visit")))
        await settle { reads.calls == 2 }
        XCTAssertNil(model.observation)
        XCTAssertEqual(model.status, .loading)
        reads.finish(.success(snapshot("New visit")))
        await settle { !delays.pending.isEmpty }
        XCTAssertEqual(model.observation?.value.processes.first?.processName, "New visit")
        model.setPopoverVisible(false)
        delays.finish()
        await settle { delays.cancellations == 1 }
        XCTAssertEqual(reads.calls, 2)
    }

    func testFailedRefreshRetainsTimestampAndPriorDataUntilFreshSuccess() async {
        let reads = Reads(), delays = Delays()
        var date = Date(timeIntervalSince1970: 1234)
        let model = SleepAssertionsViewModel(read: reads.read, now: { date }, wait: delays.wait)
        model.setDiagnosticsVisible(true)
        model.setPopoverVisible(true)
        await settle { reads.calls == 1 }
        reads.finish(.failure(.unsupportedFormat))
        await settle { !delays.pending.isEmpty }
        XCTAssertEqual(model.status, .failure)
        XCTAssertNil(model.observation)
        XCTAssertTrue(model.failureMessage.contains("isn’t supported"))
        delays.finish()
        await settle { reads.calls == 2 }
        reads.finish(.success(snapshot("Exporter")))
        await settle { !delays.pending.isEmpty }
        let lastUpdated = model.observation?.updatedAt
        delays.finish()
        await settle { reads.calls == 3 }
        date.addTimeInterval(5)
        reads.finish(.failure(.malformedFormat))
        await settle { !delays.pending.isEmpty }
        XCTAssertEqual(model.status, .failure)
        XCTAssertEqual(model.observation?.updatedAt, lastUpdated)
        XCTAssertEqual(model.observation?.value.processes.first?.processName, "Exporter")
        delays.finish()
        await settle { reads.calls == 4 }
        XCTAssertEqual(model.status, .loading)
        XCTAssertNotNil(model.error)
        XCTAssertEqual(model.observation?.updatedAt, lastUpdated)
        reads.finish(.success(snapshot()))
        await settle { !delays.pending.isEmpty }
        XCTAssertEqual(model.status, .success)
        XCTAssertEqual(model.observation?.value.processes, [])
        XCTAssertEqual(model.observation?.updatedAt, date)
        XCTAssertNil(model.error)
        model.setPopoverVisible(false)
        delays.finishAll()
    }

    func testSuspensionStopsPollingAndResumeReadsAgain() async {
        let reads = Reads(), delays = Delays()
        let model = SleepAssertionsViewModel(read: reads.read, now: Date.init, wait: delays.wait)
        model.setPopoverVisible(true)
        model.setDiagnosticsVisible(true)
        await settle { reads.calls == 1 }
        reads.finish(.success(snapshot()))
        await settle { !delays.pending.isEmpty }
        model.setSuspended(true)
        delays.finish()
        await settle { delays.cancellations == 1 }
        XCTAssertEqual(model.status, .idle)
        XCTAssertEqual(reads.calls, 1)
        model.setSuspended(false)
        await settle { reads.calls == 2 }
        model.setPopoverVisible(false)
        reads.finish(.failure(.malformedFormat))
        await settle { reads.cancellations == 1 }
        XCTAssertNil(model.error)
    }

    func testUnsettledChildPausesAllRetriesIncludingCancelledVisitAndReopen() async {
        for reopenBeforeCompletion in [false, true] {
            let reads = Reads(), delays = Delays()
            let model = SleepAssertionsViewModel(read: reads.read, now: Date.init, wait: delays.wait)
            model.setPopoverVisible(true)
            model.setDiagnosticsVisible(true)
            await settle { reads.calls == 1 }
            if reopenBeforeCompletion {
                model.setPopoverVisible(false)
                model.setPopoverVisible(true)
            }
            let outcome = CommandOutcome(stdout: Data(), stderr: Data(), termination: .timedOut,
                outputComplete: false, outputTruncated: false, directChildStopped: false)
            reads.finish(.failure(.commandFailed(outcome)))
            await settle { model.pollingPaused }
            XCTAssertEqual(model.status, .failure)
            XCTAssertTrue(model.failureMessage.contains("paused for this app session"))
            model.refresh()
            model.setPopoverVisible(false)
            model.setPopoverVisible(true)
            model.refresh()
            XCTAssertTrue(model.pollingPaused)
            XCTAssertEqual(model.status, .failure)
            XCTAssertEqual(reads.calls, 1)
            XCTAssertTrue(delays.pending.isEmpty)
            XCTAssertNil(model.observation)
        }
    }

    func testOwnerDeallocationCancelsReadAndScheduledWait() async {
        let reads = Reads(), delays = Delays()
        var model: SleepAssertionsViewModel? = SleepAssertionsViewModel(read: reads.read, now: Date.init, wait: delays.wait)
        weak var weakModel = model
        model?.setPopoverVisible(true)
        model?.setDiagnosticsVisible(true)
        await settle { reads.calls == 1 }
        model = nil
        XCTAssertNil(weakModel)
        reads.finish(.success(snapshot()))
        await settle { reads.cancellations == 1 }
        XCTAssertTrue(delays.pending.isEmpty)
        model = SleepAssertionsViewModel(read: reads.read, now: Date.init, wait: delays.wait)
        weakModel = model
        model?.setPopoverVisible(true)
        model?.setDiagnosticsVisible(true)
        await settle { reads.calls == 2 }
        reads.finish(.success(snapshot()))
        await settle { !delays.pending.isEmpty }
        model = nil
        XCTAssertNil(weakModel)
        delays.finish()
        await settle { delays.cancellations == 1 }
    }
}
