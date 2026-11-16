import Foundation

enum SleepAssertionCategory: String, CaseIterable {
    case idleSleep, systemSleep, displaySleep, other
}

struct SleepAssertion: Identifiable, Equatable {
    let id: String
    let type: String
    let name: String
    var details: [String]
    let isSuspended: Bool
    let isTimedOut: Bool

    // A logged timeout does not necessarily release an assertion (TimeoutActionLog).
    // The owning-process section already reports held assertions; only an explicit
    // suspension takes this row out of the active groups.
    var isActive: Bool { !isSuspended }

    var category: SleepAssertionCategory {
        switch type {
        case "PreventUserIdleSystemSleep", "NoIdleSleepAssertion": return .idleSleep
        case "PreventSystemSleep": return .systemSleep
        case "PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion": return .displaySleep
        default: return .other
        }
    }
}

struct SleepAssertionProcess: Identifiable, Equatable {
    // A friendly label is never process identity. Group only within this observation;
    // PID reuse across refreshes must not create process history.
    var id: String { "\(pid):\(processName)" }
    let pid: Int
    let processName: String
    var assertions: [SleepAssertion]

    var displayName: String {
        switch processName {
        case "powerd": return "Power Management"
        case "WindowServer": return "Window Server"
        case "sharingd": return "Sharing / Handoff"
        case "coreaudiod": return "Audio Service"
        case "cloudd": return "iCloud"
        case "bluetoothd": return "Bluetooth"
        case "apsd": return "Apple Push Service"
        default: return processName
        }
    }
}

/// A single complete `pmset -g assertions` observation, never an execution policy.
/// Output grammar is based on Apple's PowerManagement/pmset/pmset.m and current
/// macOS output. Future or ambiguous formats fail closed instead of implying sleep
/// is unopposed. The read transport separately rejects truncated/incomplete bytes.
struct SleepAssertions: Equatable {
    let summary: [String: Int]
    let processes: [SleepAssertionProcess]
    let kernelSummary: String?
    let kernelDetails: [String]
    let sleepPreventers: [String]

    /// pmset mixes encodings within a line: process names and kernel/localized
    /// text are UTF-8, but assertion names, details, resources and beneficiary
    /// descriptions are MacRoman (PowerManagement/pmset/pmset.m). Decode only
    /// those delimited fields as MacRoman; a whole-output fallback would corrupt
    /// process identity or accept malformed structural bytes.
    static func parse(_ data: Data) -> Result<SleepAssertions, DiagnosticReadError> {
        var lines: [String] = []
        for line in data.split(separator: 0x0a, omittingEmptySubsequences: false) {
            let bytes = Array(line)
            guard let decoded = decodeLine(bytes) else { return .failure(.malformedFormat) }
            lines.append(decoded)
        }
        return parse(lines.joined(separator: "\n"))
    }

    static func parse(_ output: String) -> Result<SleepAssertions, DiagnosticReadError> {
        enum Section { case prefix, summary, owners, kernel, preventers }
        var section = Section.prefix
        var summary: [String: Int] = [:]
        var processes: [SleepAssertionProcess] = []
        var kernelSummary: String?
        var kernelDetails: [String] = []
        var sleepPreventers: [String] = []
        var ownerSectionSeen = false
        var kernelSectionSeen = false
        var explicitNoOwners = false
        var lastOwner: (process: Int, assertion: Int)?

        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line == "Assertion status system-wide:" {
                guard section == .prefix else { return .failure(.malformedFormat) }
                section = .summary
                continue
            }
            if line == "Listed by owning process:" {
                guard section == .summary, !summary.isEmpty else { return .failure(.malformedFormat) }
                ownerSectionSeen = true
                section = .owners
                continue
            }
            if line == "No kernel assertions." || line.hasPrefix("Kernel Assertions:") {
                guard section == .owners else { return .failure(.malformedFormat) }
                if line != "No kernel assertions." {
                    guard let fields = captures(#"^Kernel Assertions: (0x[0-9a-fA-F]+)(?:=([A-Za-z0-9_,]+))?$"#, in: line),
                          let bits = UInt64(fields[0].dropFirst(2), radix: 16), bits > 0 else {
                        return .failure(.malformedFormat)
                    }
                    kernelSummary = fields[1].isEmpty ? fields[0] : fields[1]
                }
                kernelSectionSeen = true
                section = .kernel
                continue
            }
            if line.hasPrefix("Idle sleep preventers:") || line.hasPrefix("System sleep preventers:") {
                guard section == .kernel || section == .preventers,
                      let separator = line.firstIndex(of: ":"),
                      !line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces).isEmpty,
                      !line.hasSuffix("...") else { return .failure(.malformedFormat) }
                section = .preventers
                sleepPreventers.append(line)
                continue
            }

            switch section {
            case .prefix:
                // pmset prints this timestamp before the summary. It is not a freshness
                // clock: the caller records completion using its injected clock.
                guard captures(#"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} [+-]\d{4}$"#, in: line) != nil else {
                    return .failure(.unsupportedFormat)
                }
            case .summary:
                guard let fields = captures(#"^([A-Za-z][A-Za-z0-9]*)\s+([0-9]+)$"#, in: line),
                      let value = Int(fields[1]), summary[fields[0]] == nil else {
                    return .failure(.malformedFormat)
                }
                summary[fields[0]] = value
            case .owners:
                if line == "None" {
                    guard processes.isEmpty, !explicitNoOwners else { return .failure(.malformedFormat) }
                    explicitNoOwners = true
                    continue
                }
                if line.hasPrefix("pid ") {
                    guard !explicitNoOwners,
                          let fields = captures(ownerPattern, in: line),
                          let pid = Int(fields[0]), pid > 0,
                          let assertionID = UInt64(fields[2].dropFirst(2), radix: 16), assertionID > 0,
                          !fields[1].trimmingCharacters(in: .whitespaces).isEmpty else {
                        return .failure(.malformedFormat)
                    }
                    let assertion = SleepAssertion(id: fields[2].lowercased(), type: fields[3], name: fields[4],
                                                   details: [], isSuspended: !fields[6].isEmpty,
                                                   isTimedOut: !fields[5].isEmpty)
                    let index: Int
                    if let existing = processes.firstIndex(where: { $0.pid == pid && $0.processName == fields[1] }) {
                        index = existing
                    } else {
                        processes.append(SleepAssertionProcess(pid: pid, processName: fields[1], assertions: []))
                        index = processes.count - 1
                    }
                    // Duplicate IDs cannot silently overwrite differing assertion data.
                    // Exact repeats are coalesced only after their detail lines are read.
                    processes[index].assertions.append(assertion)
                    lastOwner = (index, processes[index].assertions.count - 1)
                } else {
                    guard let owner = lastOwner, isSupportedDetail(line) else { return .failure(.unsupportedFormat) }
                    processes[owner.process].assertions[owner.assertion].details.append(line)
                }
            case .kernel:
                guard kernelSummary != nil,
                      line == "None" || captures(#"^(?:id=[0-9]+\s*)?(?:by \[0x[0-9a-fA-F]+\])?\s*level=[0-9]+ 0x[0-9a-fA-F]+(?:=[A-Za-z0-9_,]+)?(?:\s.*)?$"#, in: line) != nil else {
                    return .failure(.unsupportedFormat)
                }
                kernelDetails.append(line)
            case .preventers:
                return .failure(.unsupportedFormat)
            }
        }

        guard ownerSectionSeen, kernelSectionSeen,
              summary["PreventUserIdleSystemSleep"] != nil,
              summary["PreventSystemSleep"] != nil,
              summary["PreventUserIdleDisplaySleep"] != nil,
              kernelSummary == nil || !kernelDetails.isEmpty else { return .failure(.unsupportedFormat) }

        for index in processes.indices {
            var seen: [String: SleepAssertion] = [:]
            var unique: [SleepAssertion] = []
            for assertion in processes[index].assertions {
                if let prior = seen[assertion.id] {
                    guard prior == assertion else { return .failure(.malformedFormat) }
                } else {
                    seen[assertion.id] = assertion
                    unique.append(assertion)
                }
            }
            processes[index].assertions = unique
        }

        // The summary and owner list are separate OS reads. A race or missing owner
        // must not turn an active assertion into a successful empty result.
        for (key, value) in summary where value > 0 {
            let aliases: Set<String>
            switch key {
            case "PreventUserIdleSystemSleep": aliases = [key, "NoIdleSleepAssertion"]
            case "PreventUserIdleDisplaySleep": aliases = [key, "NoDisplaySleepAssertion"]
            default: aliases = [key]
            }
            guard processes.contains(where: { process in
                process.assertions.contains { aliases.contains($0.type) && $0.isActive }
            }) else { return .failure(.unsupportedFormat) }
        }
        return .success(SleepAssertions(summary: summary, processes: processes, kernelSummary: kernelSummary,
                                        kernelDetails: kernelDetails, sleepPreventers: sleepPreventers))
    }

    private static let ownerPattern = #"^pid ([0-9]+)\((.+)\): \[(0x[0-9a-fA-F]{1,16})\] (?:[0-9]+:[0-5][0-9]:[0-5][0-9]\s+)?([A-Za-z][A-Za-z0-9]*) named: \"(.*)\"\s*(\(timed out\))?\s*(\(Suspended\))?$"#

    private static func decodeLine(_ rawBytes: [UInt8]) -> String? {
        // Trim only ASCII indentation/CRLF, never Unicode whitespace interpreted
        // from undecoded bytes. NUL and other control bytes cannot come from the
        // supported printf fields and must not be repaired into readable output.
        let bytes = Array(rawBytes.drop(while: { $0 == 0x20 || $0 == 0x09 })
            .reversed().drop(while: { $0 == 0x20 || $0 == 0x09 || $0 == 0x0d }).reversed())
        guard bytes.allSatisfy({ $0 >= 0x20 || $0 == 0x09 }) else { return nil }
        // One scalar/UTF-16 unit per byte gives regex ranges byte-exact offsets.
        // Map high bytes into private-use scalars so MacRoman bytes such as 85 (Ö)
        // cannot be mistaken for Unicode whitespace by the structural regex.
        // This view locates ASCII delimiters only; it is never decoded text.
        let byteView = String(bytes.map { byte in
            Character(UnicodeScalar(byte < 0x80 ? UInt32(byte) : 0xe000 + UInt32(byte))!)
        })
        let field: (pattern: String, capture: Int)?
        if byteView.hasPrefix("pid ") { field = (ownerPattern, 5) }
        else if byteView.hasPrefix("Details: ") { field = (#"^Details: (.+)$"#, 1) }
        else if byteView.hasPrefix("Resources: ") { field = (#"^Resources: (.+)$"#, 1) }
        else if byteView.hasPrefix("Created for PID: ") { field = (#"^Created for PID: [0-9]+\. Description: (.*)$"#, 1) }
        else { field = nil }

        guard let field, let match = match(field.pattern, in: byteView) else {
            // Headers, types, Localized, timeout actions, kernel descriptions and
            // driver preventer names never receive a lossy or MacRoman fallback.
            return String(data: Data(bytes), encoding: .utf8)
        }
        let range = match.range(at: field.capture)
        guard range.location != NSNotFound,
              let prefix = String(data: Data(bytes[..<range.location]), encoding: .utf8),
              let value = String(data: Data(bytes[range.location..<NSMaxRange(range)]), encoding: .macOSRoman),
              let suffix = String(data: Data(bytes[NSMaxRange(range)...]), encoding: .utf8) else { return nil }
        return prefix + value + suffix
    }

    private static func isSupportedDetail(_ line: String) -> Bool {
        if ["Details: ", "Resources: ", "Localized="].contains(where: { line.hasPrefix($0) && line.count > $0.count }) { return true }
        if line == "Assertion applied on Battery power also" || line == "Assertion applied on AC  power only" { return true }
        return captures(#"^Created for PID: [0-9]+\.(?: Description: .*)?$"#, in: line) != nil
            || captures(#"^Timeout will fire in [0-9]+ secs Action=.+$"#, in: line) != nil
    }

    private static func captures(_ pattern: String, in string: String) -> [String]? {
        guard let match = match(pattern, in: string) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: string) else { return "" }
            return String(string[range])
        }
    }

    private static func match(_ pattern: String, in string: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        return regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string))
    }
}
