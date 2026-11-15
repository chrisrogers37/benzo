import Darwin
import Foundation

@main
struct BenzoCommandMain {
    @MainActor static func main() async {
        for number in [SIGPIPE, SIGHUP, SIGINT, SIGTERM] { signal(number, SIG_IGN) }
        do {
            guard geteuid() == 0 else { throw PowerCommandError.invalid("The Benzo command needs administrator setup.") }
            let arguments = Array(CommandLine.arguments.dropFirst())
            if let verb = arguments.first, ["install-v1", "repair-v1", "remove-v1"].contains(verb) {
                try CommandInstaller.perform(arguments: arguments)
                return
            }
            guard arguments.count == 1, PowerCommandVerb(rawValue: arguments[0]) != nil else {
                throw PowerCommandError.invalid("Unsupported Benzo command arguments.")
            }
            // Capture sudo's preserved real UID before normalizing our already
            // elevated credentials. Never derive this identity from JSON/env.
            let caller = try CommandToolIdentity.localOwner(uid: getuid())
            guard setgroups(0, nil) == 0, setgid(0) == 0, setuid(0) == 0 else {
                throw PowerCommandError.invalid("The command execution credentials could not be established.")
            }
            let input = try PowerCommandWire.decode(verb: arguments[0], data: CommandRuntime.readInput())
            let store = try PowerCommandStore()
            let engine = PowerCommandEngine(store: store, bootID: {
                guard let uuid = UUID(uuidString: try BootIdentityProvider.bootID()) else {
                    throw PowerCommandError.invalid("The current boot identity is invalid.")
                }
                return uuid
            }, capture: { cell in try await CommandRuntime.capture(cell) },
               execute: { cell, value in await CommandRuntime.execute(cell, value: value) },
               revalidateOwner: { owner in
                   guard try CommandToolIdentity.localOwner(uid: owner.uid) == owner else {
                       throw PowerCommandError.invalid("The authorized local account has changed.")
                   }
               })
            let reply = await engine.handle(input, caller: caller)
            CommandRuntime.writeReply(try PowerCommandWire.encode(reply))
            withExtendedLifetime(store) {}
        } catch {
            fputs(PowerCommandWire.reason(error.localizedDescription) + "\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
