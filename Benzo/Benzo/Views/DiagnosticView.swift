import SwiftUI
import AppKit

struct DiagnosticView: View {
    @ObservedObject var viewModel: BenzoViewModel
    let maximumContentHeight: () -> CGFloat
    let onBack: () -> Void
    @FocusState private var backFocused: Bool
    @AccessibilityFocusState private var backAccessibilityFocused: Bool
    @State private var scrollMarker = NSView(frame: .zero)
    @State private var heightLimit: CGFloat = 600
    @State private var headerHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            header
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: DiagnosticHeaderHeightKey.self, value: geometry.size.height)
                    }
                }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sleepSessionsPanel
                    wakeReasonPanel
                    usbDevicesPanel
                    observedSettingsPanel
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    DiagnosticScrollMarker(view: scrollMarker)
                        .frame(width: 0, height: 0)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxHeight: min(400, max(0, heightLimit - headerHeight)))
            .focusable()
            .accessibilityLabel("Diagnostic results")
            .onMoveCommand { direction in
                switch direction {
                case .up: scrollDiagnostics(down: false)
                case .down: scrollDiagnostics(down: true)
                default: break
                }
            }
            .onCommand(#selector(NSResponder.scrollPageUp(_:))) {
                scrollDiagnostics(down: false, page: true)
            }
            .onCommand(#selector(NSResponder.scrollPageDown(_:))) {
                scrollDiagnostics(down: true, page: true)
            }
            .onCommand(#selector(NSResponder.pageUp(_:))) {
                scrollDiagnostics(down: false, page: true)
            }
            .onCommand(#selector(NSResponder.pageDown(_:))) {
                scrollDiagnostics(down: true, page: true)
            }
        }
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .background(BenzoTheme.surface)
        .onPreferenceChange(DiagnosticHeaderHeightKey.self) { headerHeight = $0 }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            heightLimit = maximumContentHeight()
        }
        .onAppear {
            heightLimit = maximumContentHeight()
            viewModel.loadDiagnostics()
            backFocused = true
            backAccessibilityFocused = true
        }
    }

    private func scrollDiagnostics(down: Bool, page: Bool = false) {
        guard let scroll = scrollMarker.enclosingScrollView,
              let document = scroll.documentView else { return }
        let clip = scroll.contentView
        let line = max(scroll.verticalLineScroll, 1)
        let distance = page ? max(clip.bounds.height - scroll.verticalPageScroll, line) : line
        let direction: CGFloat = (down == document.isFlipped) ? 1 : -1
        var proposed = clip.bounds
        proposed.origin.y += direction * distance
        // The hosted scroll view did not move for the standard responder scroll actions.
        // Constrain the clip bounds so short content and either document orientation stay valid.
        clip.scroll(to: clip.constrainBoundsRect(proposed).origin)
        scroll.reflectScrolledClipView(clip)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(BenzoTheme.accentControl)
            }
            .buttonStyle(.plain)
            .focused($backFocused)
            .accessibilityFocused($backAccessibilityFocused)
            .overlay {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(backFocused ? BenzoTheme.accentControl : .clear, lineWidth: 2)
                    .padding(-3)
                    .allowsHitTesting(false)
            }

            Spacer()

            Text("Diagnostics")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(BenzoTheme.text)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            // Balance the back button width
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                Text("Back")
                    .font(.system(size: 11, weight: .medium))
            }
            .opacity(0)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(BenzoTheme.surface)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.5)
        }
    }

    // MARK: - Sleep Sessions

    private var sleepSessionsPanel: some View {
        panelContainer(title: "Recent Sleep Sessions") {
            switch viewModel.sleepData {
            case .idle, .loading:
                loadingRow
            case .failure:
                emptyRow("Could not read sleep history")
            case .success(let data):
                if data.sessions.isEmpty {
                    emptyRow("No sleep sessions reported")
                } else {
                    ForEach(data.sessions) { session in sleepSessionRow(session) }
                }
            }
        }
    }

    private func sleepSessionRow(_ session: SleepSession) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 0) {
                Text(formatDate(session.sleepTime))
                    .font(.system(size: 11, weight: .medium))
                if let wake = session.wakeTime {
                    Text(" → ")
                        .font(.system(size: 11))
                        .foregroundColor(BenzoTheme.textFaint)
                    Text(formatTime(wake))
                        .font(.system(size: 11, weight: .medium))
                }
                Spacer()
            }
            .foregroundColor(BenzoTheme.text)

            Text(session.formattedDuration)
                .font(.system(size: 11))
                .foregroundColor(BenzoTheme.textMuted)

            if let s = session.batteryAtSleep, let w = session.batteryAtWake {
                let delta = session.batteryDelta ?? 0
                Text("\(s)% → \(w)% (\(delta > 0 ? "+" : "")\(delta)%)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(delta == 0 ? BenzoTheme.positiveText : BenzoTheme.textMuted)
            }

            if session.wakeReason != nil {
                Text(session.humanWakeReason)
                    .font(.system(size: 11))
                    .foregroundColor(BenzoTheme.textMuted)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: - Wake Reason

    private var wakeReasonPanel: some View {
        panelContainer(title: "Last Wake Reason") {
            switch viewModel.sleepData {
            case .idle, .loading:
                loadingRow
            case .failure:
                emptyRow("Could not read sleep history")
            case .success(let data):
                HStack {
                    let reason = data.lastWakeReason.map(SleepSession.humanReadableReason) ?? "Unknown"
                    Image(systemName: wakeReasonIcon(reason))
                        .font(.system(size: 11))
                        .foregroundColor(BenzoTheme.accent)
                        .frame(width: 16)
                    Text(reason)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(BenzoTheme.text)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: - USB Devices

    private var usbDevicesPanel: some View {
        panelContainer(title: "Connected USB Devices") {
            switch viewModel.usbDevices {
            case .idle, .loading:
                loadingRow
            case .failure(let error):
                emptyRow(usbFailureMessage(error))
            case .success(let devices):
                if devices.isEmpty {
                    emptyRow("No USB devices reported")
                } else {
                    ForEach(devices) { device in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(device.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(BenzoTheme.text)
                                .fixedSize(horizontal: false, vertical: true)
                            if let power = device.power {
                                Text("\(power.label): \(power.value)")
                                    .font(.system(size: 11))
                                    .foregroundColor(BenzoTheme.textMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    }
                    if devices.contains(where: { $0.power != nil }) {
                        emptyRow("Reported requirements or allocations, not measured power use.")
                    }
                }
            }
        }
    }

    // MARK: - Current Settings

    private var observedSettingsPanel: some View {
        panelContainer(title: "Current Settings") {
            switch viewModel.observedSettings {
            case .idle, .loading:
                loadingRow
            case .failure:
                emptyRow("Could not read settings")
            case .success(let settings):
                ForEach(settings) { setting in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .top, spacing: 8) {
                            Text(setting.displayName)
                                .foregroundColor(BenzoTheme.text)
                            Spacer(minLength: 4)
                            Text(setting.displayValue)
                                .foregroundColor(BenzoTheme.textMuted)
                                .multilineTextAlignment(.trailing)
                        }
                        .font(.system(size: 11))
                        Text(setting.rawDetail)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(BenzoTheme.textMuted)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
                Text("Current values reported by macOS.")
                    .font(.system(size: 11))
                    .foregroundColor(BenzoTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
        }
    }

    // MARK: - Helpers

    private func panelContainer<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(BenzoTheme.text)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 6)

            content()
        }
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.3)
        }
    }

    private var loadingRow: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.6)
            Text("Loading...")
                .font(.system(size: 11))
                .foregroundColor(BenzoTheme.textMuted)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(BenzoTheme.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
    }

    private func usbFailureMessage(_ error: DiagnosticReadError) -> String {
        switch error {
        case .unsupportedFormat: return "USB reporting is unavailable on this Mac"
        case .malformedFormat: return "Could not interpret the USB report"
        case .incompleteCapture: return "The USB report was incomplete"
        case .commandFailed: return "Could not read USB devices"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private func wakeReasonIcon(_ reason: String) -> String {
        if reason.contains("Lid") { return "laptopcomputer" }
        if reason.contains("Power Button") { return "power" }
        if reason.contains("USB") { return "cable.connector" }
        if reason.contains("Network") || reason.contains("WoL") { return "network" }
        if reason.contains("Scheduled") { return "alarm" }
        if reason.contains("Notification") { return "bell" }
        return "questionmark.circle"
    }
}

private struct DiagnosticHeaderHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// Resolve the existing scroll view from its content rather than replacing its layout.
private struct DiagnosticScrollMarker: NSViewRepresentable {
    let view: NSView

    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
