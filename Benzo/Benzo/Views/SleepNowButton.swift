import SwiftUI

struct SleepNowButton: View {
    let isSleeping: Bool
    let onSleep: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSleep) {
            HStack(spacing: 8) {
                if isSleeping {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    Text("Sleeping...")
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
    }
}
