import SwiftUI

struct SetupView: View {
    let observation: PermissionObservation
    let onRefresh: () -> Void
    let onBack: () -> Void

    private var statusText: String {
        switch observation {
        case .noLegacyRule:
            return "No legacy permission rule found"
        case .legacyRulePresent:
            return "Legacy permission rule found; authorization is unverified"
        case .unknown:
            return "Permission status could not be determined"
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("💊")
                .font(.system(size: 36))

            Text("Permission status")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(BenzoTheme.text)

            Text(statusText)
                .font(.system(size: 12))
                .foregroundColor(BenzoTheme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Button(action: onRefresh) {
                Text("Refresh status")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background(BenzoTheme.accentControl)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)

            Button("Back", action: onBack)
                .font(.system(size: 12))
                .foregroundColor(BenzoTheme.textMuted)
                .buttonStyle(.plain)

            Text("This only checks for a legacy rule. It does not verify authorization or change permissions.")
                .font(.system(size: 10))
                .foregroundColor(BenzoTheme.textFaint)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Spacer()
        }
        .frame(width: 320)
        .background(BenzoTheme.surface)
    }
}
