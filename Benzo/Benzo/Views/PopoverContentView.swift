import SwiftUI

struct PopoverContentView: View {
    @ObservedObject var viewModel: BenzoViewModel
    @State private var showOptions = false

    var body: some View {
        if viewModel.needsSetup {
            SetupView(
                onSetup: viewModel.runSetup,
                errorMessage: viewModel.errorMessage
            )
        } else if viewModel.showDiagnostics {
            DiagnosticView(viewModel: viewModel, onBack: {
                viewModel.showDiagnostics = false
            })
        } else {
            mainView
        }
    }

    private var mainView: some View {
        VStack(spacing: 0) {
            MasterToggleView(
                isActive: viewModel.isActive,
                activeCount: viewModel.activeCount,
                onToggle: viewModel.toggleMaster
            )

            SleepNowButton(isSleeping: viewModel.isSleeping, onSleep: viewModel.sleepNow)
                .padding(.horizontal, 20)
                .padding(.bottom, 14)

            if viewModel.isActive && !viewModel.sleepBlockers.isEmpty {
                let names = viewModel.sleepBlockers.map(\.displayName).joined(separator: ", ")
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 9))
                        Text("\(viewModel.sleepBlockers.count) app\(viewModel.sleepBlockers.count == 1 ? "" : "s") may prevent sleep:")
                            .font(.system(size: 11))
                    }
                    Text(names)
                        .font(.system(size: 10))
                }
                .foregroundColor(BenzoTheme.textMuted)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            }

            Divider().opacity(0.5)

            // Collapsible options
            HStack {
                Text("Options")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(BenzoTheme.textMuted)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(BenzoTheme.textFaint)
                    .rotationEffect(.degrees(showOptions ? 90 : 0))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                showOptions.toggle()
            }

            if showOptions {
                VStack(spacing: 0) {
                    ForEach(SleepSetting.allCases) { setting in
                        SettingRowView(
                            setting: setting,
                            isEnabled: viewModel.settingStates[setting] ?? false,
                            isActive: viewModel.isActive,
                            onToggle: { viewModel.toggleSetting(setting) }
                        )
                    }
                }
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider().opacity(0.3)

            FooterView(
                launchAtLogin: $viewModel.launchAtLogin,
                onRevert: viewModel.revertToDefaults,
                onQuit: viewModel.quit
            )
        }
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .background(BenzoTheme.surface)
    }
}
