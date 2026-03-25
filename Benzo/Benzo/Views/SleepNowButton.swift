import AppKit
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
        Button(action: handleClick) {
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
                } else if showTimerPicker {
                    timerPills
                } else {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 11))
                    Text("Sleep Now")
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(BenzoTheme.accent)
                    .shadow(color: isHovered ? BenzoTheme.accent.opacity(0.35) : BenzoTheme.accent.opacity(0.15), radius: isHovered ? 12 : 6, y: 2)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isSleeping)
        .opacity(isSleeping ? 0.7 : 1)
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .animation(.easeInOut(duration: 0.2), value: isSleeping)
        .animation(.easeInOut(duration: 0.2), value: showTimerPicker)
        .animation(.easeInOut(duration: 0.2), value: isCountingDown)
    }

    // MARK: - Subviews

    private var timerPills: some View {
        HStack(spacing: 8) {
            ForEach([5, 15, 30], id: \.self) { minutes in
                Text("\(minutes)m")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(BenzoTheme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.9)))
                    .onTapGesture {
                        showTimerPicker = false
                        onTimedSleep(TimeInterval(minutes * 60))
                    }
            }
        }
    }

    // MARK: - Actions

    private func handleClick() {
        if isCountingDown {
            onCancelTimer()
        } else if NSEvent.modifierFlags.contains(.command) {
            showTimerPicker.toggle()
        } else if showTimerPicker {
            showTimerPicker = false
        } else {
            onSleep()
        }
    }

    // MARK: - Formatting

    private var formattedTime: String {
        guard let remaining = sleepTimerRemaining else { return "" }
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
