import SwiftUI

struct SleepNowButton: View {
    let onSleep: () -> Void

    var body: some View {
        VStack(spacing: 6) {
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
            }
            .buttonStyle(.plain)
            .background(Capsule().fill(BenzoTheme.accent))
            .clipShape(Capsule())
            .disabled(true)
            .opacity(0.5)
            .help(BenzoViewModel.sleepUnavailableReason)

            Text(BenzoViewModel.sleepUnavailableReason)
                .font(.system(size: 10))
                .foregroundColor(BenzoTheme.textMuted)
                .multilineTextAlignment(.center)
        }
    }
}
