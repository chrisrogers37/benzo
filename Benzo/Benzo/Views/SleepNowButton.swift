import SwiftUI

struct SleepNowButton: View {
    let isSleeping: Bool
    let sleepTimerRemaining: TimeInterval?
    let onSleep: () -> Void
    let onTimedSleep: (TimeInterval) -> Void
    let onCancelTimer: () -> Void

    @State private var isHovered = false
    @State private var showTimerPicker = false

    private var isCountingDown: Bool {
        sleepTimerRemaining != nil
    }

    var body: some View {
        Group {
            if isSleeping || isCountingDown {
                statusCapsule
            } else {
                splitCapsule
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .animation(.easeInOut(duration: 0.2), value: isSleeping)
        .animation(.easeInOut(duration: 0.2), value: showTimerPicker)
        .animation(.easeInOut(duration: 0.2), value: isCountingDown)
    }

    // MARK: - Default / picker states (split capsule)

    private var splitCapsule: some View {
        HStack(spacing: 0) {
            if showTimerPicker {
                pickerSection
            } else {
                sleepNowSection
            }

            Rectangle()
                .fill(Color.white.opacity(0.22))
                .frame(width: 1, height: 16)

            timerToggleButton
        }
        .background(
            Capsule()
                .fill(BenzoTheme.accent)
                .shadow(
                    color: isHovered ? BenzoTheme.accent.opacity(0.35) : BenzoTheme.accent.opacity(0.15),
                    radius: isHovered ? 12 : 6,
                    y: 2
                )
        )
        .clipShape(Capsule())
        .onHover { isHovered = $0 }
    }

    private var sleepNowSection: some View {
        Button(action: onSleep) {
            HStack(spacing: 8) {
                Image(systemName: "moon.fill")
                    .font(.system(size: 11))
                Text("Sleep Now")
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var pickerSection: some View {
        HStack(spacing: 8) {
            ForEach([5, 15, 30, 60], id: \.self) { minutes in
                Button {
                    showTimerPicker = false
                    onTimedSleep(TimeInterval(minutes * 60))
                } label: {
                    Text("\(minutes)m")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(BenzoTheme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.9)))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private var timerToggleButton: some View {
        Button {
            showTimerPicker.toggle()
        } label: {
            Image(systemName: showTimerPicker ? "xmark" : "clock")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 38)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(showTimerPicker ? "Close timer" : "Set sleep timer")
    }

    // MARK: - Sleeping / countdown states

    private var statusCapsule: some View {
        Button(action: handleStatusClick) {
            HStack(spacing: 8) {
                if isSleeping {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    Text("Sleeping...")
                } else if isCountingDown {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 11))
                    Text("Sleeping in \(formattedTime)")
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .disabled(isSleeping)
        .opacity(isSleeping ? 0.7 : 1)
        .background(
            Capsule()
                .fill(BenzoTheme.accent)
                .shadow(color: BenzoTheme.accent.opacity(0.15), radius: 6, y: 2)
        )
        .clipShape(Capsule())
    }

    private func handleStatusClick() {
        if isCountingDown {
            onCancelTimer()
        }
    }

    private var formattedTime: String {
        guard let remaining = sleepTimerRemaining else { return "" }
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
