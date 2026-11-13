import Darwin
import Foundation

/// Normal exchanges are noninteractive. Only explicit setup actions elevate.
@MainActor
final class CommandToolClient: HelperSetupClient {
    private let runner: CommandRunner
    private let setup: CommandToolSetup

    init(runner: CommandRunner) {
        self.runner = runner
        setup = CommandToolSetup(runner: runner)
    }

    func refresh() async -> HelperReadiness {
        do {
            _ = try await version()
            // Recovery owns pending execution; access can be ready while the
            // coordinator consumes a durable receipt from a previous process.
            return .ready
        } catch CommandToolClientError.missing { return .notInstalled }
        catch CommandToolClientError.differentAccount { return .differentAccount }
        catch CommandToolClientError.incompatible { return .unavailable(.incompatible) }
        catch { return .unavailable(.connection) }
    }

    func register() async throws -> HelperReadiness {
        try await setup.perform(.install)
        return await refresh()
    }
    func authorizeCurrentAccount() async throws -> HelperReadiness { try await register() }
    func replace() async throws -> HelperReadiness {
        try await setup.perform(.replace)
        return await refresh()
    }
    func remove() async throws -> HelperReadiness {
        try await setup.perform(.remove)
        return await refresh()
    }
    // Protocol compatibility only; the new UI has no background-service step.
    func openApprovalSettings() {}

    func version() async throws -> PowerCommandReply {
        let reply = try await exchange(.version, payload: Data())
        guard reply.outcome == .version, reply.grantEpoch != nil,
              reply.highWaterMark != nil, reply.bootID != nil else {
            throw CommandToolClientError.unavailable
        }
        try reply.pending?.validate()
        return reply
    }

    func prepare(cell: ManagedCell, value: Int, expectedValue: Int,
                 operationID: UUID, bootID: String) async throws -> PowerCommandRequest {
        let status = try await version()
        guard let epoch = status.grantEpoch, let watermark = status.highWaterMark,
              watermark < UInt64.max, let boot = status.bootID,
              boot == UUID(uuidString: bootID) else {
            throw PowerCommandError.invalid("Power access changed. Refresh Benzo before trying again.")
        }
        guard status.pending == nil else {
            throw PowerCommandError.invalid("A previous request needs recovery. Refresh recovery before another change.")
        }
        let request = PowerCommandRequest(grantEpoch: epoch, sequence: watermark + 1,
            requestID: UUID(), operationID: operationID, bootID: boot,
            profile: cell.profile, key: cell.key, expectedValue: expectedValue, target: value)
        try request.validate()
        return request
    }

    func write(_ request: PowerCommandRequest) async -> RecoveryWriteOutcome {
        do {
            let reply = try await exchange(.write, payload: JSONEncoder().encode(request))
            return try reply.recoveryOutcome(for: request)
        } catch {
            return .uncertain("The settings request has no complete response. Refresh recovery to check its saved result.")
        }
    }

    func reconcile(_ request: PowerCommandRequest) async -> RecoveryFenceResolution? {
        do {
            let reply = try await exchange(.status, payload: JSONEncoder().encode(request.token))
            if let result = try reply.recoveryResolution(for: request) { return result }
            // Seal never starts pmset: it reports existing execution or bars a
            // delayed request durably, including after acknowledgement.
            let sealed = try await exchange(.seal, payload: JSONEncoder().encode(request))
            return try sealed.recoveryResolution(for: request)
        } catch { return nil }
    }

    func acknowledge(_ request: PowerCommandRequest) async throws {
        let reply = try await exchange(.ack, payload: JSONEncoder().encode(request.token))
        guard reply.token == request.token, reply.outcome == .acknowledged else {
            throw PowerCommandError.invalid("The saved result could not be acknowledged. Refresh recovery before another change.")
        }
    }

    private func exchange(_ verb: PowerCommandVerb, payload: Data) async throws -> PowerCommandReply {
        guard payload.count <= PowerCommandWire.maximumInputBytes else { throw CommandToolClientError.incompatible }
        try Self.verifyInstalledExecutable()
        let owner = try CommandToolIdentity.currentOwner()
        let result = await runner.run(request: CommandRequest(executable: "/usr/bin/sudo",
            arguments: ["-n", "--", CommandToolIdentity.installedPath, verb.rawValue],
            timeout: 35, maximumOutputBytes: PowerCommandWire.maximumReplyBytes,
            standardInput: payload,
            environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "C", "LC_ALL": "C"]))
        guard result.isSuccess, result.directChildStopped, result.stderr.isEmpty,
              !result.stdout.isEmpty else { throw CommandToolClientError.unavailable }
        let reply = try JSONDecoder().decode(PowerCommandReply.self, from: result.stdout)
        guard reply.schema == 1, reply.protocolVersion == 1 else { throw CommandToolClientError.incompatible }
        if reply.outcome == .differentAccount { throw CommandToolClientError.differentAccount }
        if let returnedOwner = reply.owner, returnedOwner != owner { throw CommandToolClientError.differentAccount }
        guard reply.owner == owner else { throw CommandToolClientError.unavailable }
        if case .denied(let reason) = reply.outcome { throw PowerCommandError.invalid(reason) }
        return reply
    }

    private static func verifyInstalledExecutable() throws {
        for (path, kind) in [("/Library", S_IFDIR), ("/Library/PrivilegedHelperTools", S_IFDIR),
                             (CommandToolIdentity.installedPath, S_IFREG)] {
            var info = stat()
            guard lstat(path, &info) == 0 else {
                if errno == ENOENT { throw CommandToolClientError.missing }
                throw CommandToolClientError.unavailable
            }
            guard info.st_uid == 0, info.st_mode & S_IFMT == kind, info.st_mode & 0o022 == 0,
                  kind != S_IFREG || (info.st_nlink == 1 && info.st_mode & 0o111 != 0) else {
                throw CommandToolClientError.unavailable
            }
        }
    }
}

private enum CommandToolClientError: LocalizedError {
    case missing, unavailable, incompatible, differentAccount
    var errorDescription: String? {
        switch self {
        case .missing: return "Set up Power Access before changing settings."
        case .unavailable: return "Power Access is unavailable. Open Setup to check or repair access; recovery records are retained."
        case .incompatible: return "Power Access needs an update. Restore settings with the previous Benzo version before updating access."
        case .differentAccount: return "Use the Mac account that completed Benzo setup."
        }
    }
}
