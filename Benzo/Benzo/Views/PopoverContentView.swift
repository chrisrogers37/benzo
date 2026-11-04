import SwiftUI

struct PopoverContentView: View {
    @ObservedObject var viewModel: BenzoViewModel
    @State private var showOptions = false
    @State private var returningFromDiagnostics = false
    private enum Control: Hashable { case options, diagnostics }
    @FocusState private var focusedControl: Control?
    @AccessibilityFocusState private var accessibilityFocus: Control?

    var body: some View {
        if viewModel.showPermissionStatus {
            SetupView(
                observation: viewModel.permissionObservation,
                onRefresh: viewModel.refreshPermissionObservation,
                onBack: { viewModel.showPermissionStatus = false }
            )
        } else if viewModel.showDiagnostics {
            DiagnosticView(viewModel: viewModel, onBack: {
                returningFromDiagnostics = true
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

            SleepNowButton(onSleep: viewModel.sleepNow)
                .padding(.horizontal, 20)
                .padding(.bottom, 14)

            Divider().opacity(0.5)

            // Collapsible options
            Button {
                showOptions.toggle()
            } label: {
                HStack {
                    Text("Options")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(BenzoTheme.textMuted)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(BenzoTheme.textFaint)
                        .rotationEffect(.degrees(showOptions ? 90 : 0))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(showOptions ? "Expanded" : "Collapsed")
            .focused($focusedControl, equals: .options)
            .overlay {
                Rectangle().stroke(focusedControl == .options ? BenzoTheme.accentControl : .clear, lineWidth: 2)
                    .allowsHitTesting(false)
            }

            if showOptions {
                let isEditBlocked = viewModel.isActive || viewModel.isSelectionEditBlocked
                VStack(spacing: 0) {
                    if isEditBlocked {
                        Text(BenzoViewModel.selectionEditBlockedReason)
                            .font(.system(size: 10))
                            .foregroundColor(BenzoTheme.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 6)
                    }
                    ForEach(SleepSetting.allCases) { setting in
                        SettingRowView(
                            setting: setting,
                            isEnabled: viewModel.settingStates[setting] ?? false,
                            isEditBlocked: isEditBlocked,
                            onToggle: { viewModel.toggleSetting(setting) }
                        )
                    }
                }
            }

            Button {
                viewModel.showDiagnostics = true
            } label: {
                Text("Diagnostics")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(BenzoTheme.accentControl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focused($focusedControl, equals: .diagnostics)
            .accessibilityFocused($accessibilityFocus, equals: .diagnostics)
            .overlay {
                Rectangle().stroke(focusedControl == .diagnostics ? BenzoTheme.accentControl : .clear, lineWidth: 2)
                    .allowsHitTesting(false)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(BenzoTheme.errorText)
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
        .onAppear {
            if returningFromDiagnostics {
                returningFromDiagnostics = false
                focusedControl = .diagnostics
                accessibilityFocus = .diagnostics
            }
        }
    }
}
