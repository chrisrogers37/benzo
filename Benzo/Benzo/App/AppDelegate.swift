import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let viewModel = AppDelegate.makeViewModel()
    private var eventMonitor: Any?
    private var sizeObserver: NSObjectProtocol?

    /// The only production composition root; it is never compiled into BenzoCoreTests.
    private static func makeViewModel() -> BenzoViewModel {
        let clock = LiveBenzoClock()
        let backupURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(BenzoPaths.supportDirectory, isDirectory: true)
            .appendingPathComponent(BenzoPaths.backupFilename)
        let dependencies = BenzoDependencies(
            commands: ShellCommandRunner(),
            backup: BackupService(fileURL: backupURL, clock: clock),
            preferences: UserDefaults.standard,
            clock: clock,
            loginItem: LiveLoginItemClient(),
            isSetupComplete: { ShellExecutor.isSetupComplete },
            needsSudoersUpdate: { ShellExecutor.needsSudoersUpdate },
            installSudoersRule: { try ShellExecutor.installSudoersRule() },
            fetchSleepData: { DiagnosticService.fetchSleepData() },
            fetchUSBDevices: { DiagnosticService.fetchUSBDevices() },
            fetchSleepBlockers: { DiagnosticService.fetchSleepBlockers() },
            verifySettings: { DiagnosticService.verifySettings(settingStates: $0, isActive: $1) },
            runInBackground: { DispatchQueue.global(qos: .userInitiated).async(execute: $0) },
            runOnMain: { DispatchQueue.main.async(execute: $0) },
            terminate: { NSApplication.shared.terminate(nil) }
        )
        return BenzoViewModel(dependencies: dependencies, startupPolicy: .automatic)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: 44)

        if let button = statusItem.button {
            updateIcon(active: viewModel.isActive)
            button.action = #selector(togglePopover)
            button.target = self
        }

        let contentView = PopoverContentView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: contentView)
        hostingController.view.setFrameSize(hostingController.sizeThatFits(in: NSSize(width: 320, height: 10000)))

        popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.delegate = self
        popover.contentViewController = hostingController

        // Watch for content size changes and pin top edge
        sizeObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: hostingController.view,
            queue: .main
        ) { [weak self] _ in
            self?.adjustPopoverFrame()
        }
        hostingController.view.postsFrameChangedNotifications = true

        viewModel.onStateChange = { [weak self] active in
            self?.updateIcon(active: active)
        }
    }

    private func adjustPopoverFrame() {
        guard let contentController = popover.contentViewController,
              let window = contentController.view.window else { return }
        let oldFrame = window.frame
        let newContentSize = contentController.view.fittingSize
        let newHeight = newContentSize.height + 20 // account for popover chrome/arrow

        if abs(oldFrame.height - newHeight) > 1 {
            let newOrigin = NSPoint(x: oldFrame.origin.x, y: oldFrame.maxY - newHeight)
            let newFrame = NSRect(origin: newOrigin, size: NSSize(width: oldFrame.width, height: newHeight))
            window.setFrame(newFrame, display: true, animate: false)
        }
    }

    private func updateIcon(active: Bool) {
        guard let button = statusItem.button else { return }
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
            viewModel.showDiagnostics = optionHeld
            viewModel.verifyAndCorrectSettings()
            openPopover()
        }
    }

    private func openPopover() {
        guard let button = statusItem.button else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

// These adapters live at the app boundary so core tests cannot accidentally select them.
extension UserDefaults: PreferenceStoring {}

private struct LiveBenzoClock: BenzoClock {
    var now: Date { Date() }

    func schedule(after delay: TimeInterval, perform: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: perform)
    }

    func scheduleRepeating(every interval: TimeInterval, perform: @escaping (any BenzoCancellation) -> Void) -> any BenzoCancellation {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { timer in
            perform(TimerCancellation(timer: timer))
        }
        return TimerCancellation(timer: timer)
    }
}

private struct TimerCancellation: BenzoCancellation {
    let timer: Timer

    func cancel() {
        timer.invalidate()
    }
}
