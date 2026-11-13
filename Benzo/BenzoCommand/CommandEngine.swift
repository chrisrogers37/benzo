import Foundation

/// One admitted operation per process, additionally serialized across processes
/// by the store's lifetime lock. No daemon, retry loop, timers or automatic writes.
@MainActor
final class PowerCommandEngine {
    private let store: any PowerCommandStoring
    private let bootID: () throws -> UUID
    private let capture: (ManagedCell) async throws -> Int?
    private let execute: (ManagedCell, Int) async -> PowerCommandExecution
    private let revalidateOwner: (PowerCommandOwner) throws -> Void
    private var admitted = false
    private var poisoned = false

    init(store: any PowerCommandStoring, bootID: @escaping () throws -> UUID,
         capture: @escaping (ManagedCell) async throws -> Int?,
         execute: @escaping (ManagedCell, Int) async -> PowerCommandExecution,
         revalidateOwner: @escaping (PowerCommandOwner) throws -> Void = { _ in }) {
        self.store = store; self.bootID = bootID; self.capture = capture
        self.execute = execute; self.revalidateOwner = revalidateOwner
    }

    func handle(_ input: PowerCommandInput, caller: PowerCommandOwner) async -> PowerCommandReply {
        guard !admitted, !poisoned else {
            return reply(input, outcome: .uncertain(reason: "Command admission is unavailable. This is not proof of no execution."))
        }
        admitted = true
        defer { admitted = false }
        var knownState: PowerCommandState?
        var currentBoot: UUID?
        do {
            try caller.validate()
            try validate(input)
            var state = try store.load()
            try state.validate()
            guard state.owner == caller else {
                return reply(input, outcome: .differentAccount)
            }
            try revalidateOwner(caller)
            let boot = try checkedBoot()
            knownState = state; currentBoot = boot
            switch input {
            case .version:
                return reply(input, state: state, boot: boot, outcome: .version)
            case .status(let token):
                guard token.grantEpoch == state.grantEpoch else { return denied(input, state, boot, "The grant epoch does not match.") }
                if let receipt = state.pending, receipt.request.token == token {
                    return receiptReply(receipt, state, boot)
                }
                // Even a next-sequence lookup can race a later write invocation.
                // Only seal may durably establish a no-spawn result.
                return reply(input, state: state, boot: boot,
                    outcome: .uncertain(reason: "No matching retained receipt exists. Execution is unknown; status does not seal a request."))
            case .ack(let token):
                guard token.grantEpoch == state.grantEpoch else { return denied(input, state, boot, "The grant epoch does not match.") }
                guard token.sequence <= state.highWaterMark else { return denied(input, state, boot, "The acknowledgement is for a future sequence.") }
                if let receipt = state.pending, receipt.request.sequence == token.sequence {
                    guard receipt.request.token == token, receipt.isTerminal else {
                        return denied(input, state, boot, "Only the exact retained terminal receipt may be acknowledged.")
                    }
                    state.pending = nil
                    try commit(state)
                }
                // An already retired token is an idempotent no-op. It never
                // renews a completion proof, and cannot release a newer receipt.
                return reply(input, state: state, boot: boot, outcome: .acknowledged)
            case .write(let request), .seal(let request):
                guard request.grantEpoch == state.grantEpoch else { return denied(input, state, boot, "The grant epoch does not match.") }
                if let receipt = state.pending,
                   receipt.request.sequence == request.sequence || receipt.request.requestID == request.requestID {
                    guard receipt.request == request else {
                        return reply(input, state: state, boot: boot,
                            outcome: .uncertain(reason: "A retained request identifier or sequence has different contents. It was not replayed."))
                    }
                    if case .seal = input, !receipt.isTerminal, request.bootID != boot {
                        // Explicit later-boot reconciliation is read-only. The
                        // old child cannot survive reboot, but its exit/result
                        // remains unknown. Keep the original tuple in evidence.
                        let value = try await capture(request.cell)
                        try requireUnchanged(state, owner: caller, boot: boot)
                        guard let value, request.key.isValid(value) else {
                            return reply(input, state: state, boot: boot,
                                outcome: .uncertain(reason: "The prior-boot intent needs a valid read-only capture before reconciliation."))
                        }
                        state.pending = PowerCommandReceipt(request: request, outcome: .reconciledAfterBoot(observedValue: value))
                        try commit(state)
                        return receiptReply(state.pending!, state, boot)
                    }
                    return receiptReply(receipt, state, boot)
                }
                guard request.sequence > state.highWaterMark else {
                    return reply(input, state: state, boot: boot,
                        outcome: .uncertain(reason: "The request sequence is retired. Its payload is no longer retained and it cannot execute again."))
                }
                guard state.highWaterMark < UInt64.max,
                      request.sequence == state.highWaterMark + 1 else {
                    return denied(input, state, boot, "Only the exact next sequence may be admitted.")
                }
                guard state.pending == nil else { return denied(input, state, boot, "The retained receipt must be resolved and acknowledged first.") }
                guard !Task.isCancelled else { return denied(input, state, boot, "Admission was cancelled before intent was committed.") }
                if case .seal = input {
                    // Seal never spawns. It may also retire an exact-next GUI
                    // token from a previous boot whose intent never arrived.
                    state.highWaterMark = request.sequence
                    state.pending = PowerCommandReceipt(request: request,
                        outcome: .notExecuted(reason: "The request was durably sealed before dispatch."))
                    try commit(state)
                    return receiptReply(state.pending!, state, boot)
                }
                guard request.bootID == boot else { return denied(input, state, boot, "The request belongs to a different system boot.") }

                let value = try await capture(request.cell)
                try requireUnchanged(state, owner: caller, boot: boot)
                guard !Task.isCancelled else { return denied(input, state, boot, "Admission was cancelled before intent was committed.") }
                guard value == request.expectedValue else {
                    // Durable rejection consumes the token, so a delayed copy
                    // cannot execute after the observed setting changes again.
                    state.highWaterMark = request.sequence
                    state.pending = PowerCommandReceipt(request: request,
                        outcome: .notExecuted(reason: "The current setting does not match the expected value."))
                    try commit(state)
                    return receiptReply(state.pending!, state, boot)
                }

                state.highWaterMark = request.sequence
                state.pending = PowerCommandReceipt(request: request, outcome: .intent)
                try commit(state) // No executor call is possible before this succeeds.
                knownState = state
                // Once intent is durable, caller cancellation cannot undo it.
                // The adapter waits for exactly its owned child or reports uncertainty.
                let outcome = await execute(request.cell, request.target)
                try requireUnchanged(state, owner: caller, boot: boot)
                switch outcome {
                case .uncertain(let reason):
                    return reply(input, state: state, boot: boot, outcome: .uncertain(reason: PowerCommandWire.reason(reason)))
                case .completed(let status):
                    guard (0...255).contains(status) else {
                        return reply(input, state: state, boot: boot, outcome: .uncertain(reason: "The child terminal status was invalid."))
                    }
                    state.pending!.outcome = .completed(exitStatus: status)
                case .notExecuted(let reason):
                    state.pending!.outcome = .notExecuted(reason: PowerCommandWire.reason(reason))
                }
                try commit(state)
                return receiptReply(state.pending!, state, boot)
            }
        } catch {
            // Includes failed pre-intent commits. This invocation did not spawn,
            // but a missing/failed reply never proves the request cannot later
            // arrive. Only a durable matching terminal receipt makes that claim.
            return reply(input, state: knownState, boot: currentBoot,
                outcome: .uncertain(reason: PowerCommandWire.reason(error.localizedDescription)))
        }
    }

    private func validate(_ input: PowerCommandInput) throws {
        switch input {
        case .write(let request), .seal(let request): try request.validate()
        case .status(let token), .ack(let token): try token.validate()
        case .version: break
        }
    }

    private func checkedBoot() throws -> UUID {
        let boot = try bootID()
        guard boot != PowerCommandWire.zeroUUID else { throw PowerCommandError.invalid("The system boot identity is unavailable.") }
        return boot
    }

    private func requireUnchanged(_ state: PowerCommandState, owner: PowerCommandOwner, boot: UUID) throws {
        try revalidateOwner(owner)
        guard try checkedBoot() == boot, try store.load() == state else {
            poisoned = true
            throw PowerCommandError.invalid("Command identity or evidence changed while the request was admitted.")
        }
    }

    private func commit(_ state: PowerCommandState) throws {
        do { try state.validate(); try store.commit(state) }
        catch { poisoned = true; throw error }
    }

    private func receiptReply(_ receipt: PowerCommandReceipt, _ state: PowerCommandState, _ boot: UUID) -> PowerCommandReply {
        let outcome: PowerCommandDisposition
        switch receipt.outcome {
        case .intent: outcome = .uncertain(reason: "Durable intent exists without terminal proof. This request will never be replayed.")
        case .completed(let status): outcome = .completed(exitStatus: status)
        case .notExecuted(let reason): outcome = .notExecuted(reason: reason)
        case .reconciledAfterBoot(let value): outcome = .reconciledAfterBoot(observedValue: value)
        }
        return reply(.write(receipt.request), state: state, boot: boot, outcome: outcome)
    }

    private func denied(_ input: PowerCommandInput, _ state: PowerCommandState, _ boot: UUID, _ reason: String) -> PowerCommandReply {
        reply(input, state: state, boot: boot, outcome: .denied(reason: reason))
    }

    private func reply(_ input: PowerCommandInput, state: PowerCommandState? = nil, boot: UUID? = nil,
                       outcome: PowerCommandDisposition) -> PowerCommandReply {
        let request: PowerCommandRequest?
        let token: PowerCommandToken?
        switch input {
        case .write(let value), .seal(let value): request = value; token = value.token
        case .status(let value), .ack(let value): request = nil; token = value
        case .version: request = nil; token = nil
        }
        return PowerCommandReply(token: token, request: request, owner: state?.owner,
            grantEpoch: state?.grantEpoch, highWaterMark: state?.highWaterMark, bootID: boot,
            pending: state?.pending, outcome: outcome)
    }
}
