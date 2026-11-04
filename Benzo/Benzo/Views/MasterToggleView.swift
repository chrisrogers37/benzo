import SwiftUI

struct MasterToggleView: View {
    let state: ControlState
    let canToggle: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(state.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(BenzoTheme.text)
                Text(state.message)
                    .font(.system(size: 11))
                    .foregroundColor(BenzoTheme.textMuted)
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
                Capsule().fill(isOn ? BenzoTheme.accent : Color(hex: "dddddd"))
                Circle().fill(.white).padding(2)
                    .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
            }
            .frame(width: 38, height: 22)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isOn)
    }
}
