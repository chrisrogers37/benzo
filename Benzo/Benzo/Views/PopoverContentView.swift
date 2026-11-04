import SwiftUI

struct PopoverContentView: View {
    @ObservedObject var viewModel: BenzoViewModel
    @State private var showOptions = false
    @State private var deferredConflicts: Set<ManagedCell> = []

    var body: some View {
        if viewModel.showPermissionStatus {
            SetupView(
                observation: viewModel.permissionObservation,
                onRefresh: viewModel.refreshPermissionObservation,
                onBack: { viewModel.showPermissionStatus = false }
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
                state: viewModel.controlState,
                canToggle: viewModel.canToggleMaster,
                onToggle: { Task { await viewModel.toggleMaster() } }
            )

            recoveryView

            SleepNowButton(onSleep: viewModel.sleepNow)
                .padding(.horizontal, 20)
                .padding(.bottom, 14)

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
                            isEnabled: viewModel.isSelected(setting),
                            isEditBlocked: isEditBlocked,
                            unavailableReason: viewModel.unavailableSettings[setting],
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
                canRestore: viewModel.canRestore,
                onRevert: { Task { await viewModel.revertToDefaults() } },
                onQuit: viewModel.quit
            )
        }
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .background(BenzoTheme.surface)
    }

    @ViewBuilder
    private var recoveryView: some View {
        if case .recoveryRequired = viewModel.controlState {
            VStack(alignment: .leading, spacing: 8) {
                if let capturedAt = viewModel.capturedAt {
                    Text("Captured \(capturedAt.formatted(date: .abbreviated, time: .shortened))")
                }
                if viewModel.executionUncertain {
                    Text("A previous command may still be running. Refresh only observes settings; it cannot clear execution uncertainty or authorize another write.")
                }
                ForEach(viewModel.conflicts) { conflict in
                    if deferredConflicts.contains(conflict.cell) {
                        HStack {
                            Text("Conflict deferred; recovery evidence is retained.")
                            Button("Review") { deferredConflicts.remove(conflict.cell) }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(settingName(for: conflict.cell)) · \(conflict.cell.profile.title)")
                                .fontWeight(.semibold)
                            Text("Recorded original: \(conflict.original). Observed now: \(conflict.current.map(String.init) ?? "unavailable").")
                            Text("Last verified Benzo value: \(conflict.lastVerified.map(String.init) ?? "none"). Other tools can change settings after this observation.")
                            Button("Keep Current") {
                                Task { await viewModel.resolveConflict(conflict, choice: .keepCurrent) }
                            }
                            .disabled(viewModel.executionUncertain || conflict.current == nil)
                            Button("Restore Recorded Original Anyway") {
                                Task { await viewModel.resolveConflict(conflict, choice: .restoreOriginal) }
                            }
                            .disabled(viewModel.executionUncertain || conflict.current == nil)
                            Button("Defer") { deferredConflicts.insert(conflict.cell) }
                        }
                    }
                }
                Button("Refresh Recovery Status") {
                    deferredConflicts.removeAll()
                    Task { await viewModel.reconcile() }
                }
            }
            .font(.system(size: 10))
            .foregroundColor(BenzoTheme.textMuted)
            .buttonStyle(.bordered)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    private func settingName(for cell: ManagedCell) -> String {
        SleepSetting.allCases.first { $0.pmsetKeys.contains(cell.key.rawValue) }?.label ?? cell.key.rawValue
    }

}
