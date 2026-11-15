import Foundation

@MainActor
protocol SleepScheduling {
    /// Monotonic seconds including system sleep, never wall-clock time.
    var now: TimeInterval { get }
    func schedule(after seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) -> SleepCancellation
}

@MainActor
final class SleepCancellation {
    private var action: (() -> Void)?
    init(_ action: @escaping () -> Void) { self.action = action }
    func cancel() { action?(); action = nil }
}

/// App-lifetime, memory-only countdown. Generation checks make an already queued
/// callback harmless after replace, cancel, sleep, wake, or eligibility loss.
@MainActor
final class SleepCountdown {
    static let presets = [5, 15, 30, 60]
    private let scheduler: any SleepScheduling
    private var scheduled: SleepCancellation?
    private var generation: UInt64 = 0
    private var deadline: TimeInterval?
    private var lastTick: TimeInterval?
    private(set) var remainingSeconds: Int?
    var onChange: ((Int?) -> Void)?
    var onFire: (() -> Void)?

    init(scheduler: any SleepScheduling) { self.scheduler = scheduler }

    func start(minutes: Int) {
        guard Self.presets.contains(minutes) else { return }
        cancel()
        deadline = scheduler.now + Double(minutes * 60)
        lastTick = scheduler.now
        remainingSeconds = minutes * 60
        onChange?(remainingSeconds)
        schedule(generation)
    }

    func cancel() {
        generation &+= 1
        scheduled?.cancel()
        scheduled = nil
        deadline = nil
        lastTick = nil
        remainingSeconds = nil
        onChange?(nil)
    }

    private func schedule(_ expected: UInt64) {
        scheduled = scheduler.schedule(after: 1) { [weak self] in self?.tick(expected) }
    }

    private func tick(_ expected: UInt64) {
        guard expected == generation, let deadline, let previous = lastTick else { return }
        let current = scheduler.now
        // Conservatively discard delayed/suspended callbacks. Even if AppKit's
        // wake notification is queued behind a timer, an overdue timer cannot fire.
        guard current >= previous, current - previous <= 2 else { cancel(); return }
        lastTick = current
        remainingSeconds = max(0, Int(ceil(deadline - current)))
        onChange?(remainingSeconds)
        if current >= deadline {
            cancel()
            onFire?()
        } else { schedule(expected) }
    }
}
