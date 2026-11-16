import Combine
import Foundation

/// Memory-only observations. Neither this owner nor its reader has a power-write boundary.
@MainActor
final class SleepAssertionsViewModel: ObservableObject {
    struct Observation {
        let value: SleepAssertions
        let updatedAt: Date
    }

    enum Status { case idle, loading, success, failure }
    @Published private(set) var status: Status = .idle
    @Published private(set) var observation: Observation?
    @Published private(set) var error: DiagnosticReadError?
    @Published private(set) var pollingPaused = false
    private var unsettledRead: DiagnosticReadError?
    private let read: () async -> Result<SleepAssertions, DiagnosticReadError>
    private let now: () -> Date
    private let wait: (TimeInterval) async throws -> Void
    private var request: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var generation = 0
    private var popoverVisible = false
    private var diagnosticsVisible = false
    private var suspended = false
    private var visible: Bool { popoverVisible && diagnosticsVisible && !suspended }

    init(read: @escaping () async -> Result<SleepAssertions, DiagnosticReadError>,
         now: @escaping () -> Date, wait: @escaping (TimeInterval) async throws -> Void) {
        self.read = read
        self.now = now
        self.wait = wait
    }

    deinit { request?.cancel(); timer?.cancel() }

    func setPopoverVisible(_ value: Bool) { changeVisibility { popoverVisible = value } }
    func setDiagnosticsVisible(_ value: Bool) { changeVisibility { diagnosticsVisible = value } }
    func setSuspended(_ value: Bool) { changeVisibility { suspended = value } }

    private func changeVisibility(_ change: () -> Void) {
        let wasVisible = visible
        change()
        guard wasVisible != visible else { return }
        generation += 1
        timer?.cancel()
        timer = nil
        if visible {
            if pollingPaused {
                status = .failure
                error = unsettledRead
            } else {
                status = .loading
                refresh()
            }
        } else {
            request?.cancel()
            // Retain the in-flight slot until the cancelled read actually returns.
            // Reopening cannot overlap a reader that has not settled yet.
            observation = nil
            error = nil
            status = .idle
        }
    }

    func refresh() {
        guard visible, request == nil, !pollingPaused else { return }
        timer?.cancel()
        timer = nil
        status = .loading
        // A known-stale observation stays labeled through retries, until success.
        let current = generation
        request = Task { [weak self, read] in
            let result = await read()
            guard let self else { return }
            self.request = nil
            // A bounded return is not proof the directly-owned process stopped.
            // Latch even a cancelled visit's uncertainty before admitting another
            // read. The runner still owns cleanup; this observer cannot retry it.
            if case .failure(let error) = result {
                switch error {
                case .commandFailed(let outcome), .incompleteCapture(let outcome):
                    if !outcome.directChildStopped {
                        self.pollingPaused = true
                        self.unsettledRead = error
                    }
                default: break
                }
            }
            if self.pollingPaused {
                if self.visible {
                    self.error = self.unsettledRead
                    self.status = .failure
                }
                return
            }
            guard self.generation == current, self.visible, !Task.isCancelled else {
                // A new visit waits for this old read, then obtains its own observation.
                if self.visible { self.refresh() }
                return
            }
            switch result {
            case .success(let value):
                self.observation = Observation(value: value, updatedAt: self.now())
                self.error = nil
                self.status = .success
            case .failure(let error):
                self.error = error
                self.status = .failure
            }
            self.scheduleRefresh(current)
        }
    }

    private func scheduleRefresh(_ current: Int) {
        timer = Task { [weak self, wait] in
            do { try await wait(5) } catch { return }
            guard !Task.isCancelled, let self, self.visible, self.generation == current else { return }
            self.timer = nil
            self.refresh()
        }
    }

    var failureMessage: String {
        if pollingPaused { return "Live refresh is paused for this app session because the previous read did not stop cleanly." }
        switch error {
        case .unsupportedFormat: return "This macOS sleep report isn’t supported."
        case .malformedFormat: return "The sleep report could not be understood."
        case .incompleteCapture: return "The sleep report was incomplete."
        case .commandFailed, .none: return "Could not read sleep activity."
        }
    }
}
