import SwiftUI

struct FooterView: View {
    @Binding var launchAtLogin: Bool
    @ObservedObject var updates: UpdateViewModel
    let canRestore: Bool
    let onRevert: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Launch at Login")
                    .font(.system(size: 10))
                    .foregroundColor(BenzoTheme.textMuted)

                Spacer()

                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .labelsHidden()
                    .toggleStyle(PinkToggleStyle())
                    .accessibilityLabel("Launch at Login")
                    .scaleEffect(0.6)
                    .frame(width: 36)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            HStack {
                Text(updates.version.display)
                    .font(.system(size: 10))
                    .foregroundColor(BenzoTheme.textMuted)

                Spacer()

                Button(updates.state == .checking ? "Checking…" : "Check for Updates…") {
                    updates.checkForUpdates()
                }
                .disabled(updates.state == .checking)
                .buttonStyle(.plain)
                .foregroundColor(BenzoTheme.accentControl)
                .font(.system(size: 10))
            }
            .padding(.horizontal, 20)

            if let message = updates.message {
                VStack(alignment: .leading, spacing: 5) {
                    Text(message)
                    if updates.hasUpdate {
                        Text("Compatibility isn't verified here. Review release requirements.")
                        Text("Resolve any recovery before replacing Benzo.")
                    }
                    Button(updates.hasUpdate ? "View Release" : "View Releases", action: updates.openReleasePage)
                        .buttonStyle(.plain)
                        .foregroundColor(BenzoTheme.accentControl)
                    if updates.browserOpenFailed {
                        Text("Couldn't open the browser. Visit github.com/chrisrogers37/benzo/releases.")
                    }
                }
                .font(.system(size: 10))
                .foregroundColor(BenzoTheme.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .accessibilityElement(children: .contain)
            }

            HStack {
                Spacer()

                Button("System Defaults") { onRevert() }
                    .disabled(!canRestore)
                    .help("Restore captured pre-Benzo settings. This does not reset macOS to Apple defaults.")
                    .font(.system(size: 10))
                    .foregroundColor(BenzoTheme.textMuted)
                    .buttonStyle(.plain)

                Button("Quit") { onQuit() }
                    .font(.system(size: 10))
                    .foregroundColor(BenzoTheme.textMuted)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            Text("System Defaults restores captured pre-Benzo settings.")
                .font(.system(size: 10))
                .foregroundColor(BenzoTheme.textMuted)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
        }
        .onDisappear { updates.cancelCheck() }
    }
}
