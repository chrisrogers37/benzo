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
            PinkToggle(isOn: state.isActive, action: onToggle,
                       accessibilityLabel: state.isActive ? "Restore captured settings" : "Apply selected settings")
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
    let accessibilityLabel: String

    var body: some View {
        Toggle(accessibilityLabel, isOn: Binding(get: { isOn }, set: { _ in action() }))
            .toggleStyle(PinkToggleStyle())
            .accessibilityLabel(accessibilityLabel)
    }
}

struct PinkToggleStyle: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? BenzoTheme.accentControl : BenzoTheme.controlBorder)
                    .frame(width: 44, height: 26)
                    .shadow(color: configuration.isOn ? BenzoTheme.accent.opacity(0.3) : .clear, radius: 8, y: 2)

                Circle()
                    .fill(Color.white)
                    .frame(width: 20, height: 20)
                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                    .padding(3)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: configuration.isOn)
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .overlay {
            Capsule().stroke(isFocused ? BenzoTheme.accentControl : .clear, lineWidth: 2)
                .padding(-3)
                .allowsHitTesting(false)
        }
    }
}
