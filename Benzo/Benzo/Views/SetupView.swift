import SwiftUI

struct SetupView: View {
    let readiness: HelperReadiness
    let isBusy: Bool
    let canReplaceHelper: Bool
    let canRemoveHelper: Bool
    let error: String?
    let recoveryMessage: String?
    let onRegister: () -> Void
    let onAuthorize: () -> Void
    let onReplace: () -> Void
    let onRemove: () -> Void
    let onRefresh: () -> Void
    let onBack: () -> Void
    @State private var confirmingRemoval = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("💊")
                .font(.system(size: 36))

            Text(readiness.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(BenzoTheme.text)
                .accessibilityAddTraits(.isHeader)

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
                    .foregroundColor(BenzoTheme.errorText)
                    .multilineTextAlignment(.center)
            }

            if readiness.supportsRepair, !canReplaceHelper, !isBusy {
                Text(BenzoViewModel.helperReplacementBlockedReason)
                    .font(.system(size: 12))
                    .foregroundColor(BenzoTheme.text)
                    .multilineTextAlignment(.center)
            }

            Group {
                switch readiness {
                case .notInstalled, .requiresApproval: Button("Set Up Power Access", action: onRegister)
                case .needsOwnerAuthorization: Button("Set Up Power Access", action: onAuthorize)
                case .ready, .unavailable(.incompatible), .unavailable(.connection):
                    Button("Repair / Update Power Access", action: onReplace).disabled(!canReplaceHelper)
                default: EmptyView()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(BenzoTheme.accentControl)
            .foregroundColor(.white)
            .disabled(isBusy)

            if readiness == .ready || readiness == .unavailable(.incompatible) {
                if !canRemoveHelper, !isBusy {
                    Text(BenzoViewModel.helperRemovalBlockedReason)
                        .font(.system(size: 12))
                        .foregroundColor(BenzoTheme.text)
                        .multilineTextAlignment(.center)
                }
                Button("Remove Power Access") { confirmingRemoval = true }
                    .buttonStyle(.plain)
                    .foregroundColor(BenzoTheme.accentControl)
                    .disabled(!canRemoveHelper || isBusy)
                    .confirmationDialog("Remove Benzo’s power access?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
                        Button("Remove Power Access", role: .destructive, action: onRemove)
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This removes Benzo’s power tool and permission to run it. Setup will be needed to change settings again. Your account and recovery records are retained.")
                    }
            }

            Button("Check Again", action: onRefresh)
                .buttonStyle(.plain)
                .foregroundColor(BenzoTheme.accentControl)
                .disabled(isBusy)
            Button(readiness == .ready ? "Done" : "Back", action: onBack)
                .buttonStyle(.plain)
                .foregroundColor(BenzoTheme.accentControl)

            if isBusy { ProgressView().controlSize(.small).accessibilityLabel("Checking power access") }

            Text("Setup asks for administrator approval once. Only this Mac account receives access. Benzo runs its power tool only when needed; no background service is installed.")
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
