import SwiftUI
import AppKit

struct PopoverContentView: View {
    @ObservedObject var viewModel: BenzoViewModel
    @ObservedObject var updates: UpdateViewModel
    let maximumContentHeight: () -> CGFloat
    @State private var showOptions = false
    @State private var deferredConflicts: Set<ManagedCell> = []
    @State private var returnToControl: Control?
    private enum Control: Hashable { case options, diagnostics, helperSetup }
    @FocusState private var focusedControl: Control?
    @AccessibilityFocusState private var accessibilityFocus: Control?

    var body: some View {
        if viewModel.showHelperSetup {
            BoundedPopoverScroll(maximumHeight: maximumContentHeight) {
                SetupView(
                    readiness: viewModel.helperReadiness,
                    isBusy: viewModel.isRefreshingHelper || viewModel.isPerformingHelperSetup,
                    canReplaceHelper: viewModel.canReplaceHelper,
                    canRemoveHelper: viewModel.canRemoveHelper,
                    error: viewModel.helperSetupError,
                    recoveryMessage: viewModel.hasSession ? (viewModel.hasHelperAccess ? viewModel.controlState.message : BenzoViewModel.helperRecoveryReason) : nil,
                    onRegister: { Task { await viewModel.registerHelper() } },
                    onAuthorize: { Task { await viewModel.authorizeCurrentAccount() } },
                    onReplace: { Task { await viewModel.replaceHelper() } },
                    onRemove: { Task { await viewModel.removeHelper() } },
                    onOpenSettings: viewModel.openHelperApprovalSettings,
                    onRefresh: { Task { await viewModel.refreshHelperReadiness() } },
                    onBack: {
                        returnToControl = .helperSetup
                        viewModel.showHelperSetup = false
                    }
                )
            }
        } else if viewModel.showDiagnostics {
            DiagnosticView(viewModel: viewModel, maximumContentHeight: maximumContentHeight, onBack: {
                returnToControl = .diagnostics
                viewModel.showDiagnostics = false
            })
        } else {
            BoundedPopoverScroll(maximumHeight: maximumContentHeight) { mainView }
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

            if !viewModel.hasHelperAccess {
                VStack(alignment: .leading, spacing: 5) {
                    Text(viewModel.helperReadiness.title).fontWeight(.semibold)
                    Text(viewModel.hasSession ? BenzoViewModel.helperRecoveryReason : viewModel.helperReadiness.message)
                }
                .font(.system(size: 12))
                .foregroundColor(BenzoTheme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
            }

            Button("Helper Setup") {
                viewModel.showHelperSetup = true
                Task { await viewModel.refreshHelperReadiness() }
            }
            .buttonStyle(.plain)
            .foregroundColor(BenzoTheme.accentControl)
            .focused($focusedControl, equals: .helperSetup)
            .accessibilityFocused($accessibilityFocus, equals: .helperSetup)
            .overlay {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(focusedControl == .helperSetup ? BenzoTheme.accentControl : .clear, lineWidth: 2)
                    .padding(-3)
                    .allowsHitTesting(false)
            }
            .padding(.vertical, 8)

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
                            isEnabled: viewModel.isSelected(setting),
                            isEditBlocked: isEditBlocked,
                            unavailableReason: viewModel.unavailableSettings[setting],
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
                updates: updates,
                canRestore: viewModel.canRestore,
                onRevert: { Task { await viewModel.revertToDefaults() } },
                onQuit: viewModel.quit
            )
        }
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .background(BenzoTheme.surface)
        .onAppear {
            if let returnToControl {
                self.returnToControl = nil
                focusedControl = returnToControl
                accessibilityFocus = returnToControl
            }
        }
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
                            .disabled(!viewModel.hasHelperAccess || viewModel.executionUncertain || conflict.current == nil)
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

/// Keep short panels compact while letting long setup, update and recovery
/// content scroll within the display that owns the status item.
private struct BoundedPopoverScroll<Content: View>: View {
    let maximumHeight: () -> CGFloat
    @ViewBuilder let content: Content
    @State private var naturalHeight: CGFloat = 320
    @State private var heightLimit: CGFloat = 600
    @State private var scrollMarker = NSView(frame: .zero)

    var body: some View {
        ScrollView(.vertical) {
            content
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: PopoverHeightKey.self, value: geometry.size.height)
                    }
                }
                .background {
                    PopoverScrollMarker(view: scrollMarker)
                        .frame(width: 0, height: 0)
                        .accessibilityHidden(true)
                }
        }
        .frame(width: 320, height: min(naturalHeight, heightLimit))
        .background(BenzoTheme.surface)
        .onPreferenceChange(PopoverHeightKey.self) { measured in
            if measured > 0, abs(measured - naturalHeight) > 0.5 { naturalHeight = measured }
        }
        .onAppear { heightLimit = maximumHeight() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            heightLimit = maximumHeight()
        }
        .focusable()
        .accessibilityLabel("Benzo controls")
        .onMoveCommand { direction in
            if direction == .up { scroll(down: false) }
            if direction == .down { scroll(down: true) }
        }
        .onCommand(#selector(NSResponder.scrollPageUp(_:))) { scroll(down: false, page: true) }
        .onCommand(#selector(NSResponder.scrollPageDown(_:))) { scroll(down: true, page: true) }
        .onCommand(#selector(NSResponder.pageUp(_:))) { scroll(down: false, page: true) }
        .onCommand(#selector(NSResponder.pageDown(_:))) { scroll(down: true, page: true) }
    }

    private func scroll(down: Bool, page: Bool = false) {
        guard let scroll = scrollMarker.enclosingScrollView,
              let document = scroll.documentView else { return }
        let clip = scroll.contentView
        let line = max(scroll.verticalLineScroll, 1)
        let distance = page ? max(clip.bounds.height - scroll.verticalPageScroll, line) : line
        var proposed = clip.bounds
        proposed.origin.y += (down == document.isFlipped ? 1 : -1) * distance
        clip.scroll(to: clip.constrainBoundsRect(proposed).origin)
        scroll.reflectScrolledClipView(clip)
    }
}

private struct PopoverHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct PopoverScrollMarker: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
