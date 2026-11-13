import Foundation
import Darwin

enum ReadCommand: CaseIterable, Sendable {
    case currentSettings, sleepLog, usbDevices

    var request: CommandRequest {
        switch self {
        case .currentSettings:
            return CommandRequest(executable: "/usr/bin/pmset", arguments: ["-g"], timeout: 10, maximumOutputBytes: 8 * 1_024 * 1_024)
        case .sleepLog:
            return CommandRequest(executable: "/usr/bin/pmset", arguments: ["-g", "log"], timeout: 10, maximumOutputBytes: 8 * 1_024 * 1_024)
        case .usbDevices:
            return CommandRequest(executable: "/usr/sbin/system_profiler", arguments: ["SPUSBDataType", "-json"], timeout: 30, maximumOutputBytes: 16 * 1_024 * 1_024)
        }
    }
}

protocol ReadCommandRunning {
    func run(_ command: ReadCommand) async -> CommandOutcome
}

enum Termination: Equatable, Sendable {
    case exited(Int32), signaled(Int32), timedOut, cancelled, launchFailed(String)
}

struct CommandOutcome: Sendable {
    let stdout: Data
    let stderr: Data
    let termination: Termination
    let outputComplete: Bool
    let outputTruncated: Bool
    /// Describes only the directly launched child, never descendants or a mutation fence.
    let directChildStopped: Bool

    var isSuccess: Bool {
        termination == .exited(0) && outputComplete && !outputTruncated
    }
}

/// Internal transport input. Production diagnostic consumers receive only ReadCommandRunning.
/// The executable/argv entrypoint also lets the unhosted tests run their owned fixture.
struct CommandRequest: Equatable, Sendable {
    let executable: String
    let arguments: [String]
    let timeout: TimeInterval
    let maximumOutputBytes: Int
    let finalizationReserve: TimeInterval
    let standardInput: Data?
    let environment: [String: String]?

    init(executable: String, arguments: [String], timeout: TimeInterval, maximumOutputBytes: Int,
         finalizationReserve: TimeInterval = 0.5, standardInput: Data? = nil,
         environment: [String: String]? = nil) {
        precondition(executable.hasPrefix("/"))
        precondition(timeout.isFinite && timeout > 0)
        precondition(finalizationReserve.isFinite && finalizationReserve > 0 && finalizationReserve < timeout)
        precondition(maximumOutputBytes >= 0)
        precondition((standardInput?.count ?? 0) <= 4_096)
        self.executable = executable
        self.arguments = arguments
        self.timeout = timeout
        self.maximumOutputBytes = maximumOutputBytes
        self.finalizationReserve = finalizationReserve
        self.standardInput = standardInput
        self.environment = environment
    }
}

struct CommandRunner: ReadCommandRunning {
    func run(_ command: ReadCommand) async -> CommandOutcome {
        await run(request: command.request)
    }

    // Internal seam for the single owned child fixture; no shell interpolation.
    func run(request: CommandRequest) async -> CommandOutcome {
        let execution = ReadExecution(request: request)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                execution.start(continuation)
            }
        } onCancel: {
            execution.cancel()
        }
    }
}

/// All mutable state is confined to queue. Process.run is separately dispatched so
/// a slow launch cannot block the return deadline or the caller's actor. If launch
/// resolves after the deadline, its callback still closes parent writers and asks
/// only that directly owned child to stop. A bounded return is not launch quiescence.
private final class ReadExecution: @unchecked Sendable {
    private let request: CommandRequest
    private let queue = DispatchQueue(label: "benzo.read.state")
    private let launchQueue = DispatchQueue(label: "benzo.read.launch")
    private let process = Process()
    private var continuation: CheckedContinuation<CommandOutcome, Never>?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdinPipe: Pipe?
    private var stdoutSource: DispatchSourceRead?
    private var stderrSource: DispatchSourceRead?
    private var stopTimer: DispatchSourceTimer?
    private var finishTimer: DispatchSourceTimer?
    private var deadline: DispatchTime = .distantFuture
    private var stdout = Data()
    private var stderr = Data()
    private var stdoutEOF = false
    private var stderrEOF = false
    private var stdoutClosed = true
    private var stderrClosed = true
    private var outputTruncated = false
    private var cancellationRequested = false
    private var launchAttempted = false
    private var launchResolved = false
    private var childStopped = false
    private var childTermination: Termination?
    private var stopReason: Termination?
    private var finishing = false
    private var finished = false

    init(request: CommandRequest) {
        self.request = request
    }

    func start(_ continuation: CheckedContinuation<CommandOutcome, Never>) {
        queue.async {
            self.continuation = continuation
            if self.cancellationRequested {
                self.stopReason = .cancelled
                self.finish()
                return
            }
            self.begin()
        }
    }

    func cancel() {
        queue.async {
            self.cancellationRequested = true
            guard self.continuation != nil, !self.finishing else { return }
            self.requestStop(.cancelled)
        }
    }

    private func begin() {
        let start = DispatchTime.now()
        deadline = start + request.timeout
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
        do {
            stdoutSource = try makeSource(stdoutPipe, isStdout: true)
            stderrSource = try makeSource(stderrPipe, isStdout: false)
        } catch {
            stopReason = .launchFailed(error.localizedDescription)
            try? stdoutPipe.fileHandleForWriting.close()
            try? stderrPipe.fileHandleForWriting.close()
            // A source owns its read endpoint once made; otherwise close it here.
            if stdoutSource == nil { try? stdoutPipe.fileHandleForReading.close() }
            if stderrSource == nil { try? stderrPipe.fileHandleForReading.close() }
            finish()
            return
        }

        process.executableURL = URL(fileURLWithPath: request.executable)
        process.arguments = request.arguments
        process.environment = request.environment
        if let input = request.standardInput {
            // The bounded payload fits in a pipe before launch. Keep its read end
            // open until Process has inherited it; no asynchronous writer or
            // caller-controlled file path is needed.
            let pipe = Pipe()
            stdinPipe = pipe
            do {
                try pipe.fileHandleForWriting.write(contentsOf: input)
                try pipe.fileHandleForWriting.close()
                process.standardInput = pipe
            } catch {
                try? pipe.fileHandleForWriting.close()
                try? pipe.fileHandleForReading.close()
                try? stdoutPipe.fileHandleForWriting.close()
                try? stderrPipe.fileHandleForWriting.close()
                stopReason = .launchFailed("The bounded command input could not be prepared.")
                finish()
                return
            }
        } else {
            process.standardInput = FileHandle.nullDevice
        }
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.terminationHandler = { [weak self] process in
            let termination: Termination = process.terminationReason == .exit
                ? .exited(process.terminationStatus) : .signaled(process.terminationStatus)
            self?.queue.async { [weak self] in
                guard let self else { return }
                self.childStopped = true
                self.childTermination = termination
                self.finishIfDrained()
            }
        }
        stopTimer = makeTimer(deadline: start + request.timeout - request.finalizationReserve) { [weak self] in
            self?.requestStop(.timedOut)
        }
        finishTimer = makeTimer(deadline: deadline) { [weak self] in
            self?.finish()
        }

        launchAttempted = true
        launchQueue.async {
            let failure: String?
            do {
                try self.process.run()
                failure = nil
            } catch {
                failure = error.localizedDescription
            }
            self.queue.async {
                self.launchResolved = true
                try? self.stdinPipe?.fileHandleForReading.close()
                self.stdinPipe = nil
                try? stdoutPipe.fileHandleForWriting.close()
                try? stderrPipe.fileHandleForWriting.close()
                if let failure {
                    self.childStopped = true
                    if self.stopReason == nil { self.stopReason = .launchFailed(failure) }
                    self.finish()
                } else {
                    if self.stopReason != nil { self.stopDirectChild() }
                    self.finishIfDrained()
                }
            }
        }
    }

    private func makeTimer(deadline: DispatchTime, action: @escaping () -> Void) -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: deadline)
        timer.setEventHandler(handler: action)
        timer.resume()
        return timer
    }

    private func makeSource(_ pipe: Pipe, isStdout: Bool) throws -> DispatchSourceRead {
        let handle = pipe.fileHandleForReading
        let descriptor = handle.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        guard flags != -1, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) != -1 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        if isStdout { stdoutClosed = false } else { stderrClosed = false }
        source.setEventHandler { [weak self] in
            self?.drain(descriptor, isStdout: isStdout)
        }
        source.setCancelHandler { [weak self] in
            try? handle.close()
            guard let self else { return }
            if isStdout { self.stdoutClosed = true } else { self.stderrClosed = true }
            if self.finishing { self.resumeIfClosed() } else { self.finishIfDrained() }
        }
        source.resume()
        return source
    }

    private func drain(_ descriptor: Int32, isStdout: Bool) {
        guard !finishing else { return }
        var buffer = [UInt8](repeating: 0, count: 4_096)
        // Yield after 64 KiB so a noisy writer cannot starve the other stream or timers.
        for _ in 0..<16 {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count > 0 {
                let remaining = request.maximumOutputBytes - stdout.count - stderr.count
                let retained = min(remaining, count)
                if isStdout { stdout.append(contentsOf: buffer.prefix(retained)) }
                else { stderr.append(contentsOf: buffer.prefix(retained)) }
                if retained < count { outputTruncated = true }
            } else if count == 0 {
                if isStdout { stdoutEOF = true } else { stderrEOF = true }
                closeSource(isStdout: isStdout)
                return
            } else if errno == EINTR {
                continue
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                return
            } else {
                // Read failure retains available evidence, but cannot report complete output.
                closeSource(isStdout: isStdout)
                return
            }
        }
    }

    private func closeSource(isStdout: Bool) {
        if isStdout { stdoutSource?.cancel() } else { stderrSource?.cancel() }
    }

    private func requestStop(_ reason: Termination) {
        guard !finishing else { return }
        if stopReason == nil { stopReason = reason }
        stopTimer?.cancel()
        stopDirectChild()
        // Cancellation gets the same bounded cleanup reserve, within the total budget.
        finishTimer?.schedule(deadline: min(deadline, .now() + request.finalizationReserve))
        finishIfDrained()
    }

    private func stopDirectChild() {
        guard launchResolved, !childStopped, process.isRunning else { return }
        process.terminate()
    }

    private func finishIfDrained() {
        guard !finishing, childStopped, stdoutClosed, stderrClosed else { return }
        finish()
    }

    private func finish() {
        guard !finishing else { return }
        finishing = true
        if stopReason == nil && childTermination == nil { stopReason = .timedOut }
        stopTimer?.cancel()
        finishTimer?.cancel()
        stdoutSource?.cancel()
        stderrSource?.cancel()
        resumeIfClosed()
    }

    private func resumeIfClosed() {
        guard finishing, !finished, stdoutClosed, stderrClosed else { return }
        finished = true
        let outcome = CommandOutcome(
            stdout: stdout,
            stderr: stderr,
            termination: stopReason ?? childTermination ?? .timedOut,
            outputComplete: stopReason == nil && stdoutEOF && stderrEOF,
            outputTruncated: outputTruncated,
            directChildStopped: !launchAttempted || childStopped
        )
        continuation?.resume(returning: outcome)
        continuation = nil
        stdoutSource = nil
        stderrSource = nil
        stopTimer = nil
        finishTimer = nil
    }
}
