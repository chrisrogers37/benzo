import Foundation

/// Pure policy and sequencing. Production injects authenticated peer identity,
/// locked root-owned storage, a kernel boot identity and a fixed direct executor.
@MainActor
final class HelperEngine {
    private let store: any HelperAuthorityStoring
    private let buildIdentifier: String
    private let bootID: () throws -> String
    private let capture: () async throws -> ProfileSnapshot
    private let execute: (ManagedCell, Int) async -> RecoveryWriteOutcome
    private let revalidatePeer: (HelperOwner) throws -> Void
    private var admitted = false
    private var activeRequest: HelperWriteRequest?
    private var poisoned = false
    private var knownRevision: UInt64 = 0
    private var replacementPrepared = false

    init(store: any HelperAuthorityStoring, buildIdentifier: String, bootID: @escaping () throws -> String,
         capture: @escaping () async throws -> ProfileSnapshot,
         execute: @escaping (ManagedCell, Int) async -> RecoveryWriteOutcome,
         revalidatePeer: @escaping (HelperOwner) throws -> Void) {
        self.store = store; self.bootID = bootID; self.capture = capture; self.execute = execute
        self.buildIdentifier = buildIdentifier
        self.revalidatePeer = revalidatePeer
    }

    func status(peer: HelperOwner) throws -> HelperStatus {
        try peer.validate()
        let state = try load()
        let boot = try currentBoot()
        return HelperStatus(owner: state?.owner, revision: state?.revision ?? 0,
            bootID: boot, executionUncertain: admitted || state?.blocksWrites(on: boot) == true,
            buildIdentifier: buildIdentifier, replacementPrepared: replacementPrepared)
    }

    /// Pauses new writes in this process before the app explicitly unregisters
    /// it. Durable execution evidence is neither cleared nor rewritten.
    func prepareForReplacement(peer: HelperOwner) throws -> HelperStatus {
        try peer.validate()
        guard !admitted else { throw invalid("A settings request is still running.") }
        guard let state = try load(), state.owner == peer else {
            throw invalid("Only the account that completed setup may replace this helper.")
        }
        let boot = try currentBoot()
        guard !state.blocksWrites(on: boot) else {
            throw invalid("Unresolved helper execution prevents replacement. Preserve the recovery evidence.")
        }
        try revalidatePeer(peer)
        replacementPrepared = true
        return try status(peer: peer)
    }

    func enroll(peer: HelperOwner, adminAuthorized: Bool) throws -> HelperStatus {
        try peer.validate()
        guard !admitted else { throw invalid("A settings request is still running.") }
        let state = try load()
        if let state {
            guard state.owner == peer else { throw invalid("Only the account that completed setup may use this helper.") }
            return try status(peer: peer)
        }
        guard adminAuthorized else { throw invalid("Administrator authorization is required to complete setup.") }
        _ = try currentBoot()
        try revalidatePeer(peer)
        try commit(HelperAuthorityState(owner: peer, revision: 0, lastExecution: nil))
        return try status(peer: peer)
    }

    func write(_ request: HelperWriteRequest, peer: HelperOwner) async -> HelperWriteReply {
        guard !admitted else {
            if activeRequest?.requestID == request.requestID || request.expectedRevision < knownRevision {
                return reply(request, .uncertain(reason: "This request may already be executing or have executed. It was not replayed."))
            }
            return reply(request, .notExecuted(reason: "Another settings request is still running."))
        }
        admitted = true
        activeRequest = request
        defer { admitted = false; activeRequest = nil }
        var mayHaveExecuted = false
        do {
            try peer.validate()
            guard var state = try load() else {
                return reply(request, .notExecuted(reason: "Complete helper setup before changing settings."))
            }
            guard state.owner == peer else {
                // Account replacement can reuse the numeric UID. Reject access
                // without asserting that an older request never executed for
                // the original enrolled principal.
                if request.expectedRevision < state.revision ||
                    [state.lastExecution, state.priorUncertainExecution].compactMap({ $0 })
                        .contains(where: { $0.request.requestID == request.requestID }) {
                    return reply(request, .uncertain(reason: "This account is not authorized, and this request may already have executed. It was not replayed."))
                }
                return reply(request, .notExecuted(reason: "Only the account that completed setup may use this helper."))
            }
            // A duplicate describes the original request, not merely this IPC
            // attempt. Never claim no execution when its identity may have run.
            for fence in [state.lastExecution, state.priorUncertainExecution].compactMap({ $0 }) {
                if fence.request.requestID == request.requestID {
                    guard fence.request == request else {
                        return reply(request, .uncertain(reason: "A request identifier was reused with different contents."))
                    }
                    if let status = fence.completedStatus { return reply(request, .completed(exitStatus: status)) }
                    if let reason = fence.notExecutedReason { return reply(request, .notExecuted(reason: reason)) }
                    return reply(request, .uncertain(reason: "This request has unresolved execution evidence. It was not replayed."))
                }
            }
            guard request.expectedRevision >= state.revision else {
                return reply(request, .uncertain(reason: "This older request may already have executed. It was not replayed."))
            }
            guard !replacementPrepared else {
                return reply(request, .notExecuted(reason: "The helper is paused for explicit replacement."))
            }
            try request.validate()
            try revalidatePeer(peer)
            guard !Task.isCancelled else { return reply(request, .notExecuted(reason: "The request was cancelled before execution.")) }
            let boot = try currentBoot()
            guard request.bootID == boot else {
                return reply(request, .notExecuted(reason: "The request belongs to a different system boot."))
            }
            guard !state.blocksWrites(on: boot) else {
                return reply(request, .notExecuted(reason: "Previous helper execution is unresolved. Preserve the recovery evidence."))
            }
            guard request.expectedRevision == state.revision else {
                return reply(request, .notExecuted(reason: "The request expects a future helper revision."))
            }

            let observed = try await capture()
            // Admission spans this await. Recheck every identity that can change
            // before making the durable execution claim.
            guard !Task.isCancelled else { return reply(request, .notExecuted(reason: "The request was cancelled before execution.")) }
            guard try currentBoot() == boot, try load() == state else {
                return reply(request, .notExecuted(reason: "Helper identity or execution evidence changed before dispatch."))
            }
            try revalidatePeer(peer)
            guard observed.value(for: request.cell) == request.expectedValue else {
                return reply(request, .notExecuted(reason: "The current setting does not match the expected value."))
            }
            if let previous = state.lastExecution, previous.isIncomplete {
                // blocksWrites already excluded same-boot execution and a full
                // prior-evidence slot. Capture above must succeed before advance.
                state.priorUncertainExecution = previous
            }
            state.revision += 1
            state.lastExecution = HelperExecutionFence(request: request)
            try commit(state)

            // Once intent is durable, client cancellation does not erase or replay
            // the admitted operation. The injected executor must settle exactly it.
            mayHaveExecuted = true
            let outcome = await execute(request.cell, request.target)
            switch outcome {
            case .uncertain(let message):
                return reply(request, .uncertain(reason: HelperProtocolLimits.reason(message)))
            case .completed(let status):
                guard (0...255).contains(status) else {
                    return reply(request, .uncertain(reason: "The setting executor returned an invalid completion status."))
                }
                guard try currentBoot() == boot, try load() == state else {
                    poisoned = true
                    return reply(request, .uncertain(reason: "Execution evidence changed before completion could be recorded."))
                }
                state.lastExecution!.completedStatus = status
                try commit(state)
                return reply(request, .completed(exitStatus: status))
            case .notExecuted(let message):
                guard try currentBoot() == boot, try load() == state else {
                    poisoned = true
                    return reply(request, .uncertain(reason: "Execution evidence changed before rejection could be recorded."))
                }
                let reason = HelperProtocolLimits.reason(message)
                state.lastExecution!.notExecutedReason = reason
                try commit(state)
                return reply(request, .notExecuted(reason: reason))
            }
        } catch {
            let reason = HelperProtocolLimits.reason(error.localizedDescription)
            return reply(request, poisoned || mayHaveExecuted ? .uncertain(reason: reason) : .notExecuted(reason: reason))
        }
    }

    private func currentBoot() throws -> String {
        let value = try bootID()
        guard UUID(uuidString: value)?.uuidString == value else {
            throw invalid("The current system boot could not be identified.")
        }
        return value
    }

    private func load() throws -> HelperAuthorityState? {
        guard !poisoned else { throw invalid("Helper persistence is unavailable. Preserve the recovery evidence.") }
        do {
            let state = try store.load()
            try state?.validate()
            knownRevision = state?.revision ?? 0
            return state
        } catch {
            poisoned = true
            throw error
        }
    }

    private func commit(_ state: HelperAuthorityState) throws {
        guard !poisoned else { throw invalid("Helper persistence is unavailable. Preserve the recovery evidence.") }
        do {
            try state.validate()
            try store.commit(state)
            knownRevision = state.revision
        } catch {
            poisoned = true
            throw error
        }
    }

    private func reply(_ request: HelperWriteRequest, _ outcome: HelperWriteDisposition) -> HelperWriteReply {
        HelperWriteReply(request: request, outcome: outcome, revision: knownRevision)
    }

    private func invalid(_ message: String) -> HelperProtocolError { .invalid(message) }
}
