import SwiftUI

struct MasterToggleView: View {
    let state: ControlState
    let canToggle: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(state.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(BenzoTheme.text)
                Text(state.message)
                    .font(.system(size: 11))
                    .foregroundColor(BenzoTheme.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            PinkToggle(isOn: state.isActive, action: onToggle)
                .disabled(!canToggle)
                .opacity(canToggle ? 1 : 0.5)
                .accessibilityLabel(state.isActive ? "Restore captured settings" : "Apply selected settings")
                .accessibilityValue(state.title)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

struct PinkToggle: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? BenzoTheme.accent : Color(hex: "dddddd"))
                    .frame(width: 44, height: 26)
                    .shadow(color: isOn ? BenzoTheme.accent.opacity(0.3) : .clear, radius: 8, y: 2)

                Circle()
                    .fill(Color.white)
                    .frame(width: 20, height: 20)
                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                    .padding(3)
            }
            .animation(.easeInOut(duration: 0.2), value: isOn)
        }
        .buttonStyle(.plain)
    }
}
