import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let viewModel = AppDelegate.makeViewModel()
    private let updateViewModel = AppDelegate.makeUpdateViewModel()
    private var eventMonitor: Any?
    private var terminationPending = false

    private static func makeUpdateViewModel() -> UpdateViewModel {
        UpdateViewModel(version: AppVersion(bundle: .main),
                        checker: ReleaseChecker(load: GitHubReleaseHTTP.load),
                        openURL: { NSWorkspace.shared.open($0) })
    }

    /// The only production composition root; it is never compiled into BenzoCoreTests.
    private static func makeViewModel() -> BenzoViewModel {
        let diagnostics = DiagnosticService(reader: CommandRunner())
        let preferences = UserDefaults.standard
        let observePermission: () -> PermissionObservation = {
            PermissionObserver(
                ruleURL: URL(fileURLWithPath: BenzoPaths.sudoers),
                metadata: { try FileManager.default.attributesOfItem(atPath: $0) }
            ).observe()
        }
        let store: any RecoveryStoring
        var hostID = "unavailable"
        do {
            hostID = try BootIdentityProvider.hostID()
            guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                throw RecoveryEvidenceError.invalid("The account's Application Support directory is unavailable.")
            }
            store = DurableJournal(directory: support.appendingPathComponent(BenzoPaths.supportDirectory, isDirectory: true),
                                   uid: getuid(), hostID: hostID)
        } catch {
            // An unavailable identity or store must never become an empty fresh session.
            hostID = "unavailable"
            store = UnavailableRecoveryStore(error: error)
        }
        let helper = HelperServiceClient()
        let coordinator = OperationCoordinator(
            store: store, transport: RecoveryTransport(runner: CommandRunner(), helper: helper), uid: getuid(), hostID: hostID,
            bootID: { try BootIdentityProvider.bootID() }, now: { Date() },
            legacyActive: { preferences.bool(forKey: BenzoPreferenceKey.isActive) }, legacyRule: observePermission
        )
        let dependencies = BenzoDependencies(
            coordinator: coordinator,
            preferences: preferences,
            loginItem: LiveLoginItemClient(),
            helperSetup: helper,
            observePermission: observePermission,
            fetchSleepData: { await diagnostics.fetchSleepData() },
            fetchUSBDevices: { await diagnostics.fetchUSBDevices() },
            readObservedSettings: { await diagnostics.readObservedSettings() },
            runInBackground: { work in Task.detached(priority: .userInitiated) { await work() } },
            runOnMain: { work in Task { @MainActor in work() } },
            terminate: { NSApplication.shared.terminate(nil) }
        )
        return BenzoViewModel(dependencies: dependencies, startupPolicy: .automatic)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { await viewModel.refreshHelperReadiness() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: 44)

        if let button = statusItem.button {
            updateIcon(state: viewModel.controlState)
            button.action = #selector(togglePopover)
            button.target = self
            button.setAccessibilityHelp("Open Benzo sleep controls. Diagnostics are available inside the panel.")
        }

        let contentView = PopoverContentView(viewModel: viewModel, updates: updateViewModel,
            maximumContentHeight: { [weak self] in self?.maximumPopoverContentHeight ?? 600 })
            .onExitCommand { [weak self] in self?.closePopover() }
        let hostingController = NSHostingController(rootView: contentView)
        // Let AppKit size and position its popover from SwiftUI's ideal size.
        // Observing frame changes and writing the popover window frame creates
        // a feedback loop with the hosting view's own layout constraints.
        hostingController.sizingOptions = [.preferredContentSize]

        popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.delegate = self
        popover.contentViewController = hostingController
        popover.contentSize = hostingController.preferredContentSize

        viewModel.onStateChange = { [weak self] state in
            self?.updateIcon(state: state)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        updateViewModel.cancelCheck()
        guard !terminationPending else { return .terminateLater }
        terminationPending = true
        Task { await settleTermination(sender) }
        return .terminateLater
    }

    private func settleTermination(_ application: NSApplication) async {
        while true {
            if await viewModel.prepareToQuit() {
                application.reply(toApplicationShouldTerminate: true)
                return
            }
            application.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.alertStyle = .warning
            if viewModel.isPerformingHelperSetup {
                alert.messageText = "Helper setup is still in progress."
                alert.informativeText = BenzoViewModel.helperSetupInProgressReason
                alert.addButton(withTitle: "Stay Open")
                alert.buttons[0].keyEquivalent = "\u{1b}"
                alert.runModal()
                terminationPending = false
                application.reply(toApplicationShouldTerminate: false)
                return
            }
            alert.messageText = "Benzo could not finish restoring settings."
            alert.informativeText = "\(viewModel.controlState.message)\n\nSettings may remain changed. Quit Anyway preserves the recovery evidence for the next launch."
            alert.addButton(withTitle: "Retry")
            alert.addButton(withTitle: "Stay Open")
            alert.addButton(withTitle: "Quit Anyway")
            // Escape dismisses the quit request; it never accepts unresolved restoration.
            alert.buttons[1].keyEquivalent = "\u{1b}"
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                continue
            case .alertThirdButtonReturn:
                application.reply(toApplicationShouldTerminate: true)
                return
            default:
                terminationPending = false
                application.reply(toApplicationShouldTerminate: false)
                return
            }
        }
    }

    private var maximumPopoverContentHeight: CGFloat {
        let visible = statusItem?.button?.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        return max(120, (visible?.height ?? 640) - 40)
    }

    private func updateIcon(state: ControlState) {
        guard let button = statusItem?.button else { return }
        button.setAccessibilityLabel("Benzo: \(state.title)")
        button.toolTip = "\(state.title). \(state.message)"
        if state.isBusy || { if case .recoveryRequired = state { return true }; return false }() {
            let symbol = state.isBusy ? "hourglass" : "exclamationmark.triangle.fill"
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: state.title)
            button.contentTintColor = state.isBusy ? .secondaryLabelColor : .systemOrange
            return
        }
        button.contentTintColor = nil
        let active = state.isActive
        let pink = NSColor(red: 212/255, green: 116/255, blue: 156/255, alpha: 1)

        let size = NSSize(width: 28, height: 22)
        let image = NSImage(size: size, flipped: false) { rect in
            let pillRect = NSRect(x: 4, y: 5, width: 20, height: 12)
            let pill = NSBezierPath(roundedRect: pillRect, xRadius: 6, yRadius: 6)

            if active {
                pink.setFill()
                pill.fill()
                // White divider line
                NSColor.white.withAlphaComponent(0.6).setStroke()
            } else {
                NSColor.labelColor.setStroke()
                pill.lineWidth = 1.3
                pill.stroke()
            }

            // Divider line across the middle (both states)
            let lineY = pillRect.midY
            let line = NSBezierPath()
            line.move(to: NSPoint(x: pillRect.minX + 3, y: lineY))
            line.line(to: NSPoint(x: pillRect.maxX - 3, y: lineY))
            line.lineWidth = 0.8
            if !active {
                NSColor.labelColor.setStroke()
            }
            line.stroke()

            return true
        }

        image.isTemplate = false
        button.image = image
    }

    @objc private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            // Detect ⌥-click for diagnostics
            let optionHeld = NSEvent.modifierFlags.contains(.option)
            viewModel.showHelperSetup = false
            viewModel.showDiagnostics = optionHeld
            openPopover()
        }
    }

    private func openPopover() {
        guard let button = statusItem.button else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.closePopover() }
        }
    }

    private func closePopover() {
        updateViewModel.cancelCheck()
        popover.performClose(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    func popoverDidClose(_ notification: Notification) {
        updateViewModel.cancelCheck()
    }
}

// These adapters live at the app boundary so core tests cannot accidentally select them.
extension UserDefaults: PreferenceStoring {}

private final class UnavailableRecoveryStore: RecoveryStoring {
    private let error: Error
    init(error: Error) { self.error = error }
    func acquireLock() throws { throw error }
    func loadJournal() throws -> RecoveryJournal? { throw error }
    func commitJournal(_ journal: RecoveryJournal) throws { throw error }
    func saveResolvedReceipt(_ journal: RecoveryJournal) throws { throw error }
    func loadFence() throws -> ExecutionFence? { throw error }
    func commitFence(_ fence: ExecutionFence) throws { throw error }
    func loadLegacyEvidence() throws -> Data? { throw error }
}

/// Live networking stays in the app composition boundary, outside core tests.
private enum GitHubReleaseHTTP {
    static func load(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = ReleaseChecker.timeout
        configuration.timeoutIntervalForResource = ReleaseChecker.timeout
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration, delegate: NoReleaseRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        return try await withTaskCancellationHandler(operation: {
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse,
                  response.statusCode == 200, response.url == ReleaseChecker.endpoint,
                  response.expectedContentLength <= Int64(ReleaseChecker.maximumBytes) else {
                throw ReleaseCheckError.unavailable
            }
            return (try await ReleaseChecker.collect(bytes), response)
        }, onCancel: { session.invalidateAndCancel() })
    }
}

/// This endpoint needs no redirects; fail closed on moves instead of widening its origin.
private final class NoReleaseRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
