import Combine
import Foundation

/// Owns only an explicit informational request and browser handoff.
@MainActor
final class UpdateViewModel: ObservableObject {
    enum State: Equatable {
        case idle, checking, checked(ReleaseCheckResult), offline, unavailable, unknownVersion
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var browserOpenFailed = false
    let version: AppVersion
    private let checker: ReleaseChecker
    private let openURL: (URL) -> Bool
    private var request: Task<Void, Never>?
    private var generation = 0

    init(version: AppVersion, checker: ReleaseChecker, openURL: @escaping (URL) -> Bool) {
        self.version = version
        self.checker = checker
        self.openURL = openURL
    }

    deinit { request?.cancel() }

    @discardableResult
    func checkForUpdates() -> Task<Void, Never>? {
        guard request == nil else { return nil }
        browserOpenFailed = false
        guard version.stableVersion != nil else { state = .unknownVersion; return nil }
        generation += 1
        let current = generation
        state = .checking
        let task = Task { [weak self, checker, version] in
            let result: State
            do {
                result = .checked(try await checker.check(installed: version))
            } catch is CancellationError {
                result = .idle
            } catch let error as URLError {
                result = [.notConnectedToInternet, .networkConnectionLost, .timedOut,
                          .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed].contains(error.code)
                    ? .offline : .unavailable
            } catch {
                result = .unavailable
            }
            guard let self, self.generation == current else { return }
            self.request = nil
            self.state = Task.isCancelled ? .idle : result
        }
        request = task
        return task
    }

    func cancelCheck() {
        generation += 1
        request?.cancel()
        request = nil
        if state == .checking { state = .idle }
    }

    var message: String? {
        switch state {
        case .idle, .checking: return nil
        case .checked(.current(let version)): return "You're on the latest published release (\(version))."
        case .checked(.available(let version, _)): return "Benzo \(version) is available."
        case .checked(.ahead): return "No newer stable release found."
        case .offline: return "Couldn't check for updates. Try again."
        case .unavailable: return "Update check unavailable. Try later."
        case .unknownVersion: return "Couldn't compare this build. View Releases."
        }
    }

    var hasUpdate: Bool {
        if case .checked(.available) = state { return true }
        return false
    }

    var pageURL: URL? {
        switch state {
        case .idle, .checking: return nil
        case .checked(.available(_, let page)): return page
        default: return ReleaseChecker.releasesURL
        }
    }

    func openReleasePage() {
        guard let pageURL else { return }
        browserOpenFailed = !openURL(pageURL)
    }
}
