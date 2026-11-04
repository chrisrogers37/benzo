import SwiftUI

struct SettingRowView: View {
    let setting: SleepSetting
    let isEnabled: Bool
    let isEditBlocked: Bool
    let onToggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onToggle) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(setting.label)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(BenzoTheme.text)

                    Text(setting.description)
                        .font(.system(size: 10.5))
                        .foregroundColor(BenzoTheme.textMuted)
                }

                Spacer()

                PinkCheckbox(isChecked: isEnabled)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
            .background(
                isHovered
                    ? (isEnabled ? BenzoTheme.accent.opacity(0.03) : Color.black.opacity(0.02))
                    : Color.clear
            )
        }
        .buttonStyle(.plain)
        .disabled(isEditBlocked)
        .opacity(isEditBlocked ? 0.5 : 1)
        .onHover { hovering in
            isHovered = hovering && !isEditBlocked
        }
    }
}

struct PinkCheckbox: View {
    let isChecked: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(isChecked ? BenzoTheme.accentControl : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(isChecked ? Color.clear : BenzoTheme.controlBorder, lineWidth: 1.5)
                )
                .shadow(color: isChecked ? BenzoTheme.accent.opacity(0.25) : .clear, radius: 4)
                .frame(width: 15, height: 15)

            if isChecked {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isChecked)
    }
}
