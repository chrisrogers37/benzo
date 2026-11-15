import Foundation
import Darwin

/// Starting the service never changes a power setting. All mutations require an
/// authenticated request and the engine's durable admission checks.
@main
struct BenzoHelperMain {
    @MainActor static func main() {
        do {
            guard geteuid() == 0 else { throw HelperServiceDefinition.failure("The helper requires launchd's root service context.") }
            let requirement = try HelperIdentity.requirement(for: HelperServiceDefinition.appIdentifier)
            let store = try HelperStateStore()
            let runner = CommandRunner()
            let engine = HelperEngine(store: store, buildIdentifier: try HelperIdentity.ownCodeHash(), bootID: { try BootIdentityProvider.bootID() }, capture: {
                let result = await runner.run(request: PMSetService.captureRequest)
                guard result.isSuccess, result.directChildStopped, result.stderr.isEmpty,
                      let output = String(data: result.stdout, encoding: .utf8) else {
                    throw HelperServiceDefinition.failure("The helper could not read complete power settings.")
                }
                return try ProfileSnapshot(parsing: output)
            }, execute: { cell, value in
                do {
                    return PMSetService.completion(await runner.run(request: try PMSetService.writeRequest(cell: cell, value: value)))
                } catch { return .notExecuted("The setting request was outside Benzo's supported values.") }
            }, revalidatePeer: { peer in
                guard try HelperIdentity.localOwner(uid: peer.uid) == peer else {
                    throw HelperServiceDefinition.failure("The local account identity changed before admission.")
                }
            })
            let delegate = HelperListener(engine: engine, clientRequirement: requirement)
            let listener = NSXPCListener(machServiceName: HelperServiceDefinition.machServiceName)
            listener.setConnectionCodeSigningRequirement(requirement)
            listener.delegate = delegate
            listener.resume()
            withExtendedLifetime((listener, delegate, store)) { dispatchMain() }
        } catch {
            // No automatic state removal/repair and no credentials in logs.
            fputs("Benzo helper could not initialize safely. Existing evidence was retained.\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}

private final class HelperListener: NSObject, NSXPCListenerDelegate {
    let engine: HelperEngine
    let clientRequirement: String
    init(engine: HelperEngine, clientRequirement: String) {
        self.engine = engine; self.clientRequirement = clientRequirement
    }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let uid = connection.effectiveUserIdentifier
        guard uid >= 501, uid < UInt32.max else { return false }
        connection.setCodeSigningRequirement(clientRequirement)
        connection.exportedInterface = NSXPCInterface(with: BenzoHelperXPC.self)
        connection.exportedObject = HelperEndpoint(engine: engine, uid: uid)
        connection.resume()
        return true
    }
}

private final class HelperEndpoint: NSObject, BenzoHelperXPC {
    private let engine: HelperEngine
    /// Captured from the connection, never a request field or PID lookup.
    private let uid: UInt32
    init(engine: HelperEngine, uid: UInt32) { self.engine = engine; self.uid = uid }

    func status(withReply reply: @escaping (Data?, String?) -> Void) {
        Task { @MainActor in
            do {
                let peer = try HelperIdentity.localOwner(uid: uid)
                reply(try HelperServiceDefinition.encode(engine.status(peer: peer)), nil)
            } catch { reply(nil, "Benzo could not verify helper access for this account.") }
        }
    }

    func enroll(_ authorization: Data, withReply reply: @escaping (Data?, String?) -> Void) {
        Task { @MainActor in
            do {
                let peer = try HelperIdentity.localOwner(uid: uid)
                let authorized = HelperEnrollmentAuthorization.validate(authorization)
                reply(try HelperServiceDefinition.encode(engine.enroll(peer: peer, adminAuthorized: authorized)), nil)
            } catch { reply(nil, "This account could not be authorized. Existing ownership was preserved.") }
        }
    }

    func prepareForReplacement(withReply reply: @escaping (Data?, String?) -> Void) {
        Task { @MainActor in
            do {
                let peer = try HelperIdentity.localOwner(uid: uid)
                reply(try HelperServiceDefinition.encode(engine.prepareForReplacement(peer: peer)), nil)
            } catch { reply(nil, "The helper cannot be replaced while execution or account access is unresolved.") }
        }
    }

    func write(_ data: Data, withReply reply: @escaping (Data?, String?) -> Void) {
        Task { @MainActor in
            do {
                let peer = try HelperIdentity.localOwner(uid: uid)
                let request = try HelperServiceDefinition.decode(HelperWriteRequest.self, from: data)
                let result = await engine.write(request, peer: peer)
                reply(try HelperServiceDefinition.encode(result), nil)
            } catch { reply(nil, "The helper could not validate this setting request.") }
        }
    }
}
