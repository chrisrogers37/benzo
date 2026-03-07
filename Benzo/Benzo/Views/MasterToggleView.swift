import SwiftUI

struct MasterToggleView: View {
    let isActive: Bool
    let activeCount: Int
    let onToggle: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(isActive ? "Deep Sleep is On" : "Deep Sleep is Off")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(BenzoTheme.text)

                Text(isActive
                    ? "Sedated. Your Mac can rest."
                    : "Your Mac is awake.")
                    .font(.system(size: 11))
                    .foregroundColor(BenzoTheme.textFaint)
            }

            Spacer()

            PinkToggle(isOn: isActive, action: onToggle)
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
