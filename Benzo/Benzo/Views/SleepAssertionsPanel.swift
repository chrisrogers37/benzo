import SwiftUI

struct SleepAssertionsPanel: View {
    @ObservedObject var model: SleepAssertionsViewModel
    @FocusState private var refreshFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Keeping Your Mac Awake")
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                Button(model.status == .loading ? "Refreshing…" : "Refresh", action: model.refresh)
                    .disabled(model.status == .loading || model.pollingPaused)
                    .buttonStyle(.plain)
                    .foregroundColor(BenzoTheme.accentControl)
                    .focused($refreshFocused)
                    .overlay {
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(refreshFocused ? BenzoTheme.accentControl : .clear, lineWidth: 2)
                            .padding(-3).allowsHitTesting(false)
                    }
                    .accessibilityLabel("Refresh sleep activity")
            }
            Text(model.pollingPaused ? "Live refresh paused" : "Updates every 5 seconds while Diagnostics is open.")
                .font(.system(size: 10))
                .foregroundColor(BenzoTheme.textMuted)
            if let observation = model.observation {
                Text("Last updated \(observation.updatedAt.formatted(date: .omitted, time: .standard))")
                    .font(.system(size: 10))
                    .foregroundColor(BenzoTheme.textMuted)
            } else if model.error == nil {
                Text(model.status == .loading ? "Reading sleep activity…" : "Not checked")
                    .foregroundColor(BenzoTheme.textMuted)
            }
            if model.error != nil {
                Text(model.failureMessage + (model.observation == nil ? "" : " Last successful observation — stale."))
                    .foregroundColor(BenzoTheme.errorText)
            }
            if let observation = model.observation {
                processGroup(observation.value, categories: [.idleSleep], title: "Automatic idle sleep", empty: "No automatic idle-sleep assertions reported.")
                processGroup(observation.value, categories: [.systemSleep], title: "System sleep", empty: "No system-sleep assertions reported.")
                processGroup(observation.value, categories: [.displaySleep, .other], title: "Display & other activity", empty: nil,
                             explanation: "These reports are not classified as preventing system sleep.")
                VStack(alignment: .leading, spacing: 4) {
                    Text("System information").fontWeight(.semibold).accessibilityAddTraits(.isHeader)
                    Text(observation.value.kernelSummary ?? "No kernel assertions reported")
                        .foregroundColor(BenzoTheme.textMuted)
                    Text("Kernel reports are separate from app sleep-prevention assertions.")
                        .foregroundColor(BenzoTheme.textMuted)
                    if !observation.value.kernelDetails.isEmpty || !observation.value.sleepPreventers.isEmpty {
                        DisclosureGroup("Kernel details") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array((observation.value.kernelDetails + observation.value.sleepPreventers).enumerated()), id: \.offset) { _, detail in Text(detail) }
                            }
                            .foregroundColor(BenzoTheme.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                        }
                        .tint(BenzoTheme.accentControl)
                    }
                }
            }
            Text("Automatic idle-sleep prevention does not guarantee that Sleep Now is blocked.")
                .font(.system(size: 10))
                .foregroundColor(BenzoTheme.textMuted)
        }
        .font(.system(size: 11))
        .foregroundColor(BenzoTheme.text)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Divider().opacity(0.3) }
    }

    @ViewBuilder
    private func processGroup(_ value: SleepAssertions, categories: [SleepAssertionCategory], title: String,
                              empty: String?, explanation: String? = nil) -> some View {
        let processes = value.processes.filter { $0.assertions.contains { $0.isActive && categories.contains($0.category) } }
        if !processes.isEmpty || empty != nil {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).fontWeight(.semibold).accessibilityAddTraits(.isHeader)
                if let explanation { Text(explanation).foregroundColor(BenzoTheme.textMuted) }
                if processes.isEmpty, let empty { Text(empty).foregroundColor(BenzoTheme.textMuted) }
                ForEach(processes) { process in
                    let assertions = process.assertions.filter { $0.isActive && categories.contains($0.category) }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(process.displayName).fontWeight(.medium)
                            Spacer(minLength: 4)
                            Text("PID \(process.pid)").font(.system(size: 10)).foregroundColor(BenzoTheme.textMuted)
                        }
                        ForEach(assertions) { assertion in
                            Text(assertion.name.isEmpty ? assertion.type : assertion.name)
                                .foregroundColor(BenzoTheme.textMuted)
                        }
                        DisclosureGroup("Assertion details") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(assertions) { assertion in
                                    Text(process.processName)
                                    Text("\(assertion.type) · \(assertion.id)")
                                    ForEach(Array(assertion.details.enumerated()), id: \.offset) { _, detail in Text(detail) }
                                }
                            }
                            .foregroundColor(BenzoTheme.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                        }
                        .tint(BenzoTheme.accentControl)
                    }
                }
            }
            .padding(.top, 2)
        }
    }
}
