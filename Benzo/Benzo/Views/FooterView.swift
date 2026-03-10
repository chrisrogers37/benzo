import SwiftUI

struct FooterView: View {
    @Binding var launchAtLogin: Bool
    let onRevert: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Launch at Login")
                    .font(.system(size: 10))
                    .foregroundColor(BenzoTheme.textMuted)

                Spacer()

                Toggle("", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .scaleEffect(0.6)
                    .frame(width: 36)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            HStack {
                Text("v0.2.1")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "d0d0d0"))

                Spacer()

                Button("Restore System Defaults") { onRevert() }
                    .font(.system(size: 10))
                    .foregroundColor(BenzoTheme.textMuted)
                    .buttonStyle(.plain)

                Button("Quit") { onQuit() }
                    .font(.system(size: 10))
                    .foregroundColor(BenzoTheme.textMuted)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
    }
}
