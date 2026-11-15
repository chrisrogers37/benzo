import SwiftUI

struct SleepNowButton: View {
    let canSleep: Bool
    let disabledReason: String?
    let remainingSeconds: Int?
    let isRequesting: Bool
    let message: String?
    let onSleep: () -> Void
    let onSchedule: (Int) -> Void
    let onCancel: () -> Void
    @State private var showTimerPicker = false
    @FocusState private var focusedControl: Control?
    private enum Control: Hashable { case sleep, timer, cancel, preset(Int) }

    private var countdown: String {
        let seconds = max(0, remainingSeconds ?? 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                if remainingSeconds != nil {
                    Button { onCancel(); focusedControl = .sleep } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "clock")
                            Text("Sleep in \(countdown)").monospacedDigit()
                            Image(systemName: "xmark").font(.system(size: 10))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                    }
                    .accessibilityLabel("Cancel sleep timer")
                    .accessibilityValue("\(countdown) remaining")
                    .focused($focusedControl, equals: .cancel)
                    .help("Cancel the countdown")
                } else {
                    Button(action: onSleep) {
                        HStack(spacing: 8) {
                            Image(systemName: "moon.fill")
                            Text(isRequesting ? "Requesting Sleep…" : "Sleep Now")
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                    }
                    .disabled(!canSleep)
                    .focused($focusedControl, equals: .sleep)
                    .help(disabledReason ?? "Send a sleep request using your applied settings")
                    Rectangle().fill(Color.white.opacity(0.5)).frame(width: 1, height: 18)
                    Button {
                        showTimerPicker.toggle()
                        if showTimerPicker { focusedControl = .preset(5) }
                    } label: {
                        Image(systemName: "clock").frame(width: 40).padding(.vertical, 10)
                    }
                    .disabled(!canSleep)
                    .accessibilityLabel("Sleep timer")
                    .accessibilityValue(showTimerPicker ? "Expanded" : "Collapsed")
                    .focused($focusedControl, equals: .timer)
                    .help(disabledReason ?? "Choose a sleep countdown")
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white)
            .background(Capsule().fill(canSleep || remainingSeconds != nil ? BenzoTheme.accentControl : BenzoTheme.accent.opacity(0.5)))
            .overlay {
                Capsule().stroke(focusedControl == .sleep || focusedControl == .timer || focusedControl == .cancel ? BenzoTheme.accentControl : .clear, lineWidth: 2)
                    .padding(-3).allowsHitTesting(false)
            }

            if showTimerPicker && canSleep && remainingSeconds == nil {
                HStack(spacing: 8) {
                    ForEach([5, 15, 30, 60], id: \.self) { minutes in
                        Button("\(minutes)m") {
                            showTimerPicker = false
                            onSchedule(minutes)
                            focusedControl = .cancel
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(BenzoTheme.accentControl)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().stroke(BenzoTheme.accentControl, lineWidth: 1))
                        .focused($focusedControl, equals: .preset(minutes))
                        .overlay {
                            Capsule().stroke(focusedControl == .preset(minutes) ? BenzoTheme.accentControl : .clear, lineWidth: 2)
                                .padding(-3).allowsHitTesting(false)
                        }
                        .accessibilityLabel("Sleep in \(minutes) minutes")
                    }
                }
                .padding(.top, 4)
            }
            if let message {
                Text(message).font(.system(size: 10)).foregroundColor(BenzoTheme.textMuted)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: canSleep) { if !$0 { showTimerPicker = false } }
        .onChange(of: remainingSeconds != nil) { if $0 { showTimerPicker = false } }
        .onExitCommand(perform: showTimerPicker ? { showTimerPicker = false; focusedControl = .timer } : nil)
    }
}
