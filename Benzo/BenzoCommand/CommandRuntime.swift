import Darwin
import Foundation

/// The privileged process keeps its root lock until its one owned child has
/// been reaped. A response deadline never abandons a privileged writer.
enum CommandRuntime {
    struct Result {
        let stdout: Data
        let stderr: Data
        let exitStatus: Int?
        let spawned: Bool
        let reaped: Bool
        let complete: Bool
        var succeeded: Bool { spawned && reaped && complete && exitStatus == 0 }
    }

#if !BENZO_STORAGE_TESTS
    static func readInput(timeout: TimeInterval = 5, limit: Int = PowerCommandWire.maximumInputBytes) throws -> Data {
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(timeout * 1_000_000_000)
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while true {
            guard DispatchTime.now().uptimeNanoseconds < deadline else {
                throw PowerCommandError.invalid("The command input was not completed in time.")
            }
            var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, 100)
            if ready < 0 && errno == EINTR { continue }
            guard ready >= 0 else { throw PowerCommandError.invalid("Command input is unavailable.") }
            if ready == 0 { continue }
            guard descriptor.revents & Int16(POLLNVAL | POLLERR) == 0 else {
                throw PowerCommandError.invalid("Command input was interrupted.")
            }
            let count = Darwin.read(STDIN_FILENO, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            guard count >= 0, data.count + max(0, count) <= limit else {
                throw PowerCommandError.invalid("Command input is unreadable or exceeds its limit.")
            }
            if count == 0 { return data }
            data.append(contentsOf: buffer.prefix(count))
        }
    }

    static func writeReply(_ data: Data) {
        let flags = fcntl(STDOUT_FILENO, F_GETFL)
        guard flags >= 0, fcntl(STDOUT_FILENO, F_SETFL, flags | O_NONBLOCK) == 0 else { return }
        let deadline = DispatchTime.now().uptimeNanoseconds + 2_000_000_000
        data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                guard DispatchTime.now().uptimeNanoseconds < deadline else { return }
                let count = Darwin.write(STDOUT_FILENO, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                    var descriptor = pollfd(fd: STDOUT_FILENO, events: Int16(POLLOUT), revents: 0)
                    _ = poll(&descriptor, 1, 100)
                    continue
                }
                if count <= 0 { return }
                offset += count
            }
        }
    }

    static func capture(_ cell: ManagedCell) async throws -> Int? {
        let result = run(executable: "/usr/bin/pmset", arguments: ["-g", "custom"], timeout: 10, maximumBytes: 65_536)
        guard result.succeeded, result.stderr.isEmpty,
              let text = String(data: result.stdout, encoding: .utf8) else {
            throw PowerCommandError.invalid("The command tool could not read complete power settings.")
        }
        return try ProfileSnapshot(parsing: text).value(for: cell)
    }

    static func execute(_ cell: ManagedCell, value: Int) async -> PowerCommandExecution {
        guard cell.key.isValid(value) else { return .notExecuted(reason: "Unsupported setting value.") }
        let result = run(executable: "/usr/bin/pmset",
            arguments: [cell.profile.argument, cell.key.rawValue, String(value)], timeout: 20, maximumBytes: 8_192)
        if !result.spawned { return .notExecuted(reason: "The setting command could not be started.") }
        if result.reaped, result.complete, let status = result.exitStatus { return .completed(exitStatus: status) }
        return .uncertain(reason: "The setting command did not finish normally. Execution evidence was retained.")
    }
#endif

    /// Internal callers supply only fixed system executables and closed argv.
    /// No command request can supply a path, environment, shell, or argv array.
    static func run(executable: String, arguments: [String], timeout: TimeInterval, maximumBytes: Int) -> Result {
#if BENZO_STORAGE_TESTS
        // Test composition cannot select pmset, an installer, sudo, or osascript.
        // Only these nonmutating owned-child fixtures are admitted.
        guard fixtureAllowed(executable: executable, arguments: arguments) else {
            return Result(stdout: Data(), stderr: Data(), exitStatus: nil, spawned: false, reaped: true, complete: false)
        }
#endif
        var output = [Int32](repeating: -1, count: 2), errors = [Int32](repeating: -1, count: 2)
        var nullFD: Int32 = -1
        defer { for fd in output + errors + [nullFD] where fd >= 0 { _ = Darwin.close(fd) } }
        let noChild = Result(stdout: Data(), stderr: Data(), exitStatus: nil, spawned: false, reaped: true, complete: false)
        guard pipe(&output) == 0, pipe(&errors) == 0 else { return noChild }
        nullFD = open("/dev/null", O_RDONLY | O_CLOEXEC)
        guard nullFD >= 0 else { return noChild }
        for fd in output + errors {
            guard fcntl(fd, F_SETFD, FD_CLOEXEC) == 0 else { return noChild }
        }
        for fd in [output[0], errors[0]] {
            let flags = fcntl(fd, F_GETFL)
            guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else { return noChild }
        }
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else { return noChild }
        defer { posix_spawn_file_actions_destroy(&actions) }
        guard posix_spawnattr_init(&attributes) == 0 else { return noChild }
        defer { posix_spawnattr_destroy(&attributes) }
        guard posix_spawn_file_actions_adddup2(&actions, nullFD, STDIN_FILENO) == 0,
              posix_spawn_file_actions_adddup2(&actions, output[1], STDOUT_FILENO) == 0,
              posix_spawn_file_actions_adddup2(&actions, errors[1], STDERR_FILENO) == 0 else { return noChild }
        for fd in output + errors + [nullFD] where fd > STDERR_FILENO {
            guard posix_spawn_file_actions_addclose(&actions, fd) == 0 else { return noChild }
        }
        var defaults = sigset_t(), mask = sigset_t()
        sigemptyset(&defaults); sigemptyset(&mask)
        for signal in [SIGTERM, SIGINT, SIGHUP, SIGPIPE] { sigaddset(&defaults, signal) }
        guard posix_spawnattr_setsigdefault(&attributes, &defaults) == 0,
              posix_spawnattr_setsigmask(&attributes, &mask) == 0,
              posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK)) == 0 else { return noChild }
        let words = ([executable] + arguments).map { word in word.withCString { strdup($0) } }
        let environmentWords: [String] = ["PATH=/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL=C"]
        let environment = environmentWords.map { word in word.withCString { strdup($0) } }
        defer { for word in words + environment { free(word) } }
        guard words.allSatisfy({ $0 != nil }), environment.allSatisfy({ $0 != nil }) else { return noChild }
        var argv = words + [nil], envp = environment + [nil]
        var pid: pid_t = 0
        let spawned = executable.withCString { posix_spawn(&pid, $0, &actions, &attributes, &argv, &envp) }
        guard spawned == 0, pid > 0 else { return noChild }
        _ = Darwin.close(output[1]); output[1] = -1
        _ = Darwin.close(errors[1]); errors[1] = -1
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(timeout * 1_000_000_000)
        var stdout = Data(), stderr = Data()
        var complete = true, reaped = false, forced = false
        var status: Int32 = 0
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while !reaped || output[0] >= 0 || errors[0] >= 0 {
            if !reaped {
                let waited = waitpid(pid, &status, WNOHANG)
                if waited == pid { reaped = true }
                else if waited < 0 && errno != EINTR { complete = false; break }
            }
            if DispatchTime.now().uptimeNanoseconds >= deadline || !complete {
                complete = false
                if !reaped && !forced { _ = kill(pid, SIGKILL); forced = true }
                if reaped { break }
            }
            var descriptors = [pollfd(fd: output[0], events: Int16(POLLIN), revents: 0),
                               pollfd(fd: errors[0], events: Int16(POLLIN), revents: 0)]
            let ready = poll(&descriptors, nfds_t(descriptors.count), 50)
            if ready < 0 && errno != EINTR { complete = false }
            for index in 0..<2 where descriptors[index].fd >= 0 && descriptors[index].revents != 0 {
                let fd = descriptors[index].fd
                for _ in 0..<16 {
                    let count = Darwin.read(fd, &buffer, buffer.count)
                    if count > 0 {
                        let kept = min(max(0, maximumBytes - stdout.count - stderr.count), count)
                        if index == 0 { stdout.append(contentsOf: buffer.prefix(kept)) }
                        else { stderr.append(contentsOf: buffer.prefix(kept)) }
                        if kept < count { complete = false }
                    } else if count == 0 {
                        _ = Darwin.close(fd)
                        if index == 0 { output[0] = -1 } else { errors[0] = -1 }
                        break
                    } else if errno == EINTR { continue }
                    else if errno == EAGAIN || errno == EWOULDBLOCK { break }
                    else { complete = false; break }
                }
            }
        }
        if !reaped {
            _ = kill(pid, SIGKILL)
            while true {
                let waited = waitpid(pid, &status, 0)
                if waited == pid { reaped = true; break }
                if waited < 0 && errno == EINTR { continue }
                break
            }
        }
        let normalExit = reaped && (status & 0x7f) == 0
        return Result(stdout: stdout, stderr: stderr, exitStatus: normalExit ? Int((status >> 8) & 0xff) : nil,
                      spawned: true, reaped: reaped, complete: complete && !forced)
    }

#if BENZO_STORAGE_TESTS
    private static func fixtureAllowed(executable: String, arguments: [String]) -> Bool {
        if executable == "/usr/bin/printf" { return arguments.count == 1 }
        if executable == "/bin/sleep", arguments.count == 1, let seconds = Double(arguments[0]) {
            return seconds.isFinite && seconds > 0 && seconds <= 2
        }
        if executable == "/does-not-exist/benzo-owned-fixture" { return arguments.isEmpty }
        if executable == "/usr/sbin/visudo", arguments.count == 3,
           arguments[0] == "-c", arguments[1] == "-f" {
            let file = URL(fileURLWithPath: arguments[2])
            let parent = file.deletingLastPathComponent()
            return file.lastPathComponent == "candidate" && parent.lastPathComponent.hasPrefix("benzo-policy-test-") &&
                parent.deletingLastPathComponent().standardizedFileURL.path == FileManager.default.temporaryDirectory.standardizedFileURL.path
        }
        return false
    }
#endif
}
