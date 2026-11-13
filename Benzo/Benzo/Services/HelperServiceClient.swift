import Foundation
import ServiceManagement

/// App-only boundary. Registration and interactive authorization are reached
/// exclusively from explicit setup actions, never from startup or a setting write.
@MainActor
final class HelperServiceClient: HelperSetupClient {
    private let service = SMAppService.daemon(plistName: HelperServiceDefinition.plistName)

    func refresh() async -> HelperReadiness {
        do { _ = try HelperIdentity.requirement(for: HelperServiceDefinition.helperIdentifier) }
        catch { return .unavailable(.signingUnavailable) }
        switch service.status {
        case .notRegistered: return .notInstalled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .unavailable(.connection)
        case .enabled: break
        @unknown default: return .unavailable(.connection)
        }
        do {
            let status = try await readStatus(requireMatchingBuild: false)
            guard let owner = status.owner else { return .needsOwnerAuthorization }
            guard owner == (try HelperIdentity.localOwner(uid: getuid())) else { return .differentAccount }
            guard !status.executionUncertain else { return .unavailable(.executionUncertain) }
            guard status.buildIdentifier == (try HelperIdentity.embeddedHelperCodeHash()),
                  !status.replacementPrepared else { return .unavailable(.incompatible) }
            return .ready
        } catch HelperClientError.incompatible { return .unavailable(.incompatible) }
        catch { return .unavailable(.connection) }
    }

    func register() async throws -> HelperReadiness {
        _ = try HelperIdentity.requirement(for: HelperServiceDefinition.helperIdentifier)
        try requireWritableInstallVolume()
        // Registration commonly reports authorizationRequired while leaving a
        // requiresApproval service. Show that actionable state rather than an error.
        do { try service.register() }
        catch {
            if service.status != .requiresApproval { throw error }
        }
        return await refresh()
    }

    func authorizeCurrentAccount() async throws -> HelperReadiness {
        guard service.status == .enabled else {
            throw HelperServiceDefinition.failure("Approve Benzo's helper in System Settings first.")
        }
        // Keep the reference alive through the exchange. No token is persisted.
        let authorization = try await Task.detached(priority: .userInitiated) {
            try HelperEnrollmentAuthorization()
        }.value
        let data = try await call { proxy, reply in
            proxy.enroll(authorization.externalForm, withReply: reply)
        }
        withExtendedLifetime(authorization) {}
        let status = try HelperServiceDefinition.decode(HelperStatus.self, from: data)
        guard status.schema == 1 else { throw HelperServiceDefinition.failure("The helper version does not match Benzo.") }
        return await refresh()
    }

    func replace() async throws -> HelperReadiness {
        _ = try HelperIdentity.requirement(for: HelperServiceDefinition.helperIdentifier)
        _ = try HelperIdentity.embeddedHelperCodeHash()
        try requireWritableInstallVolume()
        try await prepareForUnregistration()
        // Await actual service termination before registering the changed bundle.
        try await service.unregister()
        do { try service.register() }
        catch { if service.status != .requiresApproval { throw error } }
        return await refresh()
    }

    func remove() async throws -> HelperReadiness {
        _ = try HelperIdentity.requirement(for: HelperServiceDefinition.helperIdentifier)
        try await prepareForUnregistration()
        try await service.unregister()
        // Unregistration removes the service, not the account grant or execution
        // evidence. Reinstallation must not silently transfer ownership.
        return await refresh()
    }

    private func requireWritableInstallVolume() throws {
        // Registering a service from the distribution DMG would bind it to an
        // ejectable, read-only location. Inspect the public volume property;
        // do not rely on private translocation paths or move the app silently.
        let values = try Bundle.main.bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey])
        guard values.volumeIsReadOnly == false else {
            throw HelperServiceDefinition.failure("Move Benzo to Applications, reopen it there, then set up its helper.")
        }
    }

    private func prepareForUnregistration() async throws {
        // The view model admits this only while the account's recovery lock is
        // held and settings are resolved. The server independently quiesces writes.
        let before = try await readStatus(requireMatchingBuild: false)
        let owner = try HelperIdentity.localOwner(uid: getuid())
        guard before.owner == owner, !before.executionUncertain else {
            throw HelperServiceDefinition.failure("Resolve helper access and execution before changing its installation.")
        }
        let data = try await call { proxy, reply in proxy.prepareForReplacement(withReply: reply) }
        let prepared = try HelperServiceDefinition.decode(HelperStatus.self, from: data)
        guard prepared.schema == 1, prepared.owner == owner,
              prepared.buildIdentifier == before.buildIdentifier,
              prepared.bootID == before.bootID, prepared.revision == before.revision,
              prepared.replacementPrepared, !prepared.executionUncertain else {
            throw HelperServiceDefinition.failure("The helper did not confirm that writes are paused. Existing evidence was retained.")
        }
    }

    func openApprovalSettings() { SMAppService.openSystemSettingsLoginItems() }

    func readStatus(requireMatchingBuild: Bool = true) async throws -> HelperStatus {
        guard service.status == .enabled else {
            throw HelperServiceDefinition.failure("Benzo's helper needs setup or approval before settings can change.")
        }
        let data = try await call { proxy, reply in proxy.status(withReply: reply) }
        let status = try HelperServiceDefinition.decode(HelperStatus.self, from: data)
        guard status.schema == 1, UUID(uuidString: status.bootID) != nil else {
            throw HelperClientError.incompatible
        }
        if requireMatchingBuild {
            let expected = try HelperIdentity.embeddedHelperCodeHash()
            guard status.buildIdentifier == expected, !status.replacementPrepared else {
                throw HelperClientError.incompatible
            }
        }
        return status
    }

    func writableStatus() async throws -> HelperStatus {
        let status = try await readStatus()
        guard status.owner == (try HelperIdentity.localOwner(uid: getuid())), !status.executionUncertain else {
            throw HelperServiceDefinition.failure("This account does not have ready helper access. Review Helper Setup; recovery evidence is retained.")
        }
        return status
    }

    func sendWrite(_ request: HelperWriteRequest) async -> RecoveryWriteOutcome {
        do {
            let payload = try HelperServiceDefinition.encode(request)
            let data = try await call(timeout: 45) { proxy, reply in proxy.write(payload, withReply: reply) }
            let response = try HelperServiceDefinition.decode(HelperWriteReply.self, from: data)
            return try response.validatedOutcome(for: request)
        } catch {
            // Once a write could have been sent, even a connection error is not
            // evidence of rejection. Never reconnect and replay this request.
            return .uncertain("The helper did not return complete execution evidence. Settings may still change; keep the recovery record.")
        }
    }

    private func call(timeout: TimeInterval = 10,
                      _ invoke: @escaping (BenzoHelperXPC, @escaping (Data?, String?) -> Void) -> Void) async throws -> Data {
        let requirement = try HelperIdentity.requirement(for: HelperServiceDefinition.helperIdentifier)
        return try await withCheckedThrowingContinuation { continuation in
            let pending = HelperPendingReply(continuation)
            let connection = NSXPCConnection(machServiceName: HelperServiceDefinition.machServiceName, options: .privileged)
            pending.connection = connection
            connection.remoteObjectInterface = NSXPCInterface(with: BenzoHelperXPC.self)
            connection.setCodeSigningRequirement(requirement)
            connection.interruptionHandler = {
                Task { @MainActor in pending.finish(.failure(HelperServiceDefinition.failure("The helper connection was interrupted."))) }
            }
            connection.invalidationHandler = {
                Task { @MainActor in pending.finish(.failure(HelperServiceDefinition.failure("The helper connection became unavailable."))) }
            }
            connection.resume()
            pending.deadline = Task { @MainActor in
                do { try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000)) }
                catch { return }
                pending.finish(.failure(HelperServiceDefinition.failure("The helper response timed out.")))
            }
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                Task { @MainActor in pending.finish(.failure(error)) }
            }) as? BenzoHelperXPC else {
                pending.finish(.failure(HelperServiceDefinition.failure("The helper interface is unavailable.")))
                return
            }
            invoke(proxy) { data, message in
                Task { @MainActor in
                    if let data, message == nil, !data.isEmpty, data.count <= HelperServiceDefinition.maximumPayloadBytes {
                        pending.finish(.success(data))
                    } else {
                        pending.finish(.failure(HelperServiceDefinition.failure(message.map { String($0.prefix(512)) } ?? "The helper response was invalid.")))
                    }
                }
            }
        }
    }
}

@MainActor
private final class HelperPendingReply {
    var connection: NSXPCConnection?
    var deadline: Task<Void, Never>?
    private var continuation: CheckedContinuation<Data, Error>?
    init(_ continuation: CheckedContinuation<Data, Error>) { self.continuation = continuation }
    func finish(_ result: Result<Data, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        deadline?.cancel(); deadline = nil
        connection?.interruptionHandler = nil
        connection?.invalidationHandler = nil
        connection?.invalidate(); connection = nil
        continuation.resume(with: result)
    }
}

private enum HelperClientError: Error { case incompatible }
