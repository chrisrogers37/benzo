import SwiftUI

struct SetupView: View {
    let readiness: HelperReadiness
    let isBusy: Bool
    let canReplaceHelper: Bool
    let error: String?
    let recoveryMessage: String?
    let onRegister: () -> Void
    let onAuthorize: () -> Void
    let onReplace: () -> Void
    let onOpenSettings: () -> Void
    let onRefresh: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("💊")
                .font(.system(size: 36))

            Text(readiness.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(BenzoTheme.text)

            Text(readiness.message)
                .font(.system(size: 12))
                .foregroundColor(BenzoTheme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            if let recoveryMessage {
                Text(recoveryMessage)
                    .font(.system(size: 12))
                    .foregroundColor(BenzoTheme.text)
                    .multilineTextAlignment(.center)
            }

            if let error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            if readiness == .unavailable(.incompatible), !canReplaceHelper, !isBusy {
                Text(BenzoViewModel.helperReplacementBlockedReason)
                    .font(.system(size: 12))
                    .foregroundColor(BenzoTheme.text)
                    .multilineTextAlignment(.center)
            }

            Group {
                switch readiness {
                case .notInstalled: Button("Set Up", action: onRegister)
                case .requiresApproval: Button("Open System Settings", action: onOpenSettings)
                case .needsOwnerAuthorization: Button("Authorize This Account", action: onAuthorize)
                case .unavailable(.incompatible):
                    Button("Replace Helper", action: onReplace).disabled(!canReplaceHelper)
                default: EmptyView()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(BenzoTheme.accent)
            .disabled(isBusy)

            Button("Check Again", action: onRefresh)
                .disabled(isBusy)
            Button(readiness == .ready ? "Done" : "Back", action: onBack)

            if isBusy { ProgressView().controlSize(.small).accessibilityLabel("Checking helper setup") }

            Text("Setup may require more than one administrator approval. You can review settings and recovery information without completing setup.")
                .font(.system(size: 10))
                .foregroundColor(BenzoTheme.textFaint)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Spacer()
        }
        .padding(20)
        .frame(width: 320)
        .background(BenzoTheme.surface)
    }
}
