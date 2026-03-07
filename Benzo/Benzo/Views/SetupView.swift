import SwiftUI

struct SetupView: View {
    let onSetup: () -> Void
    var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("💊")
                .font(.system(size: 36))

            Text("Welcome to Benzo")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(BenzoTheme.text)

            Text("Benzo needs one-time permission to modify your Mac's sleep settings.")
                .font(.system(size: 12))
                .foregroundColor(BenzoTheme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                    .padding(.horizontal, 20)
            }

            Button(action: onSetup) {
                Text("Grant Permission")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background(BenzoTheme.accent)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)

            Text("This creates a system rule so Benzo\ncan adjust sleep settings without\nrepeatedly asking for your password.")
                .font(.system(size: 10))
                .foregroundColor(BenzoTheme.textFaint)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(width: 320)
        .background(BenzoTheme.surface)
    }
}
