import SwiftUI

struct DiagnosticView: View {
    @ObservedObject var viewModel: BenzoViewModel
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 0) {
                    sleepSessionsPanel
                    wakeReasonPanel
                    usbDevicesPanel
                    settingsVerificationPanel
                }
            }
            .frame(maxHeight: 400)
        }
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .background(BenzoTheme.surface)
        .onAppear { viewModel.loadDiagnostics() }
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
                .foregroundColor(BenzoTheme.accent)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Diagnostics")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(BenzoTheme.text)

            Spacer()

            // Balance the back button width
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                Text("Back")
                    .font(.system(size: 11, weight: .medium))
            }
            .opacity(0)
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
            if viewModel.isLoadingDiagnostics {
                loadingRow
            } else if viewModel.sleepSessions.isEmpty {
                emptyRow("No sleep sessions found")
            } else {
                ForEach(viewModel.sleepSessions) { session in
                    sleepSessionRow(session)
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

            HStack(spacing: 8) {
                Text(session.formattedDuration)
                    .font(.system(size: 10))
                    .foregroundColor(BenzoTheme.textMuted)

                if let s = session.batteryAtSleep, let w = session.batteryAtWake {
                    let delta = session.batteryDelta ?? 0
                    Text("\(s)% → \(w)% (\(delta > 0 ? "+" : "")\(delta)%)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(delta == 0 ? Color.green : BenzoTheme.textMuted)
                }

                if session.wakeReason != nil {
                    Text(session.humanWakeReason)
                        .font(.system(size: 10))
                        .foregroundColor(BenzoTheme.textFaint)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: - Wake Reason

    private var wakeReasonPanel: some View {
        panelContainer(title: "Last Wake Reason") {
            if viewModel.isLoadingDiagnostics {
                loadingRow
            } else {
                HStack {
                    let reason = viewModel.lastWakeReason ?? "Unknown"
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
            if viewModel.isLoadingDiagnostics {
                loadingRow
            } else if viewModel.usbDevices.isEmpty {
                emptyRow("No USB devices connected")
            } else {
                ForEach(viewModel.usbDevices) { device in
                    HStack {
                        Text(device.name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(BenzoTheme.text)
                            .lineLimit(1)
                        Spacer()
                        if let power = device.busPowerUsed {
                            Text("\(power) mA")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(BenzoTheme.textMuted)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Settings Verification

    private var settingsVerificationPanel: some View {
        panelContainer(title: "Settings Verification") {
            if viewModel.isLoadingDiagnostics {
                loadingRow
            } else if viewModel.settingsVerification.isEmpty {
                emptyRow("Could not read settings")
            } else {
                ForEach(viewModel.settingsVerification) { v in
                    HStack(spacing: 6) {
                        Image(systemName: v.matches ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(v.matches ? .green : .red)
                        Text(v.key)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(BenzoTheme.text)
                        Spacer()
                        Text(v.actualValue)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(v.matches ? BenzoTheme.textMuted : .red)
                        if !v.matches {
                            Text("(expected \(v.expectedValue))")
                                .font(.system(size: 9))
                                .foregroundColor(.red.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 3)
                }

                let matchCount = viewModel.settingsVerification.filter(\.matches).count
                let total = viewModel.settingsVerification.count
                let allMatch = matchCount == total
                HStack {
                    Spacer()
                    Text(allMatch ? "All settings verified" : "\(total - matchCount) setting\(total - matchCount == 1 ? "" : "s") drifted")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(allMatch ? .green : .red)
                    Spacer()
                }
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: - Helpers

    private func panelContainer<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(BenzoTheme.textFaint)
                .tracking(0.8)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 6)

            content()
        }
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
            .foregroundColor(BenzoTheme.textFaint)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
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
