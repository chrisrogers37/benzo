import Foundation

struct DiagnosticService {
    let reader: any ReadCommandRunning

    func fetchSleepData() async -> Result<SleepReadPayload, DiagnosticReadError> {
        await read(.sleepLog).flatMap(Self.parseSleepLog)
    }

    func fetchUSBDevices() async -> Result<[USBDevice], DiagnosticReadError> {
        await read(.usbDevices).flatMap(Self.parseUSBDevices)
    }

    func readObservedSettings() async -> Result<[ObservedSetting], DiagnosticReadError> {
        await read(.currentSettings).flatMap(Self.parseObservedSettings)
    }

    private func read(_ command: ReadCommand) async -> Result<String, DiagnosticReadError> {
        let outcome = await reader.run(command)
        guard outcome.termination == .exited(0) else { return .failure(.commandFailed(outcome)) }
        guard outcome.outputComplete, !outcome.outputTruncated else { return .failure(.incompleteCapture(outcome)) }
        guard let output = String(data: outcome.stdout, encoding: .utf8) else { return .failure(.malformedFormat) }
        return .success(output)
    }

    // MARK: - Pure parsers

    /// Supports timestamped pmset Sleep/Wake records and known non-event domains.
    /// Headers or arbitrary text alone cannot establish that no events were reported.
    static func parseSleepLog(_ log: String) -> Result<SleepReadPayload, DiagnosticReadError> {
        var sleepEvents: [(date: Date, battery: Int?)] = []
        var wakeEvents: [(date: Date, battery: Int?, reason: String?)] = []
        var recognizedRecord = false
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        formatter.isLenient = false

        for line in log.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(maxSplits: 3, whereSeparator: { $0.isWhitespace })
            let body = parts.count == 4 ? String(parts[3]) : ""
            let domain = body.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
            let sleepCandidate = trimmed.contains("Entering Sleep") || trimmed.contains("\tSleep\t") || domain == "Sleep"
            let wakeCandidate = trimmed.contains("Wake from") || trimmed.contains("\tWake\t") || (domain == "Wake" && !body.hasPrefix("Wake Requests")) || domain == "DarkWake"
            let knownOtherDomain = ["Assertions", "Kernel", "PM", "Wake", "Notification", "Start", "Summary"].contains(domain ?? "")
            guard sleepCandidate || wakeCandidate || knownOtherDomain else { continue }
            guard parts.count == 4,
                  let date = formatter.date(from: parts.prefix(3).joined(separator: " ")) else {
                return .failure(.malformedFormat)
            }
            // A recognized event domain still needs the supported event message. Never
            // discard a malformed candidate and present the remaining sessions as complete.
            if sleepCandidate && !trimmed.contains("Entering Sleep state") {
                return .failure(.unsupportedFormat)
            }
            if wakeCandidate && !trimmed.contains("Wake from") {
                return .failure(.unsupportedFormat)
            }
            recognizedRecord = true
            var battery: Int?
            if let range = trimmed.range(of: "Charge:") {
                let charge = trimmed[range.upperBound...].drop(while: { $0.isWhitespace })
                let digits = charge.prefix(while: { $0.isASCII && $0.isNumber })
                guard let value = Int(digits), (0...100).contains(value),
                      charge.dropFirst(digits.count).first.map({ $0 == "%" || $0.isWhitespace }) ?? true else {
                    return .failure(.malformedFormat)
                }
                battery = value
            }
            if sleepCandidate {
                sleepEvents.append((date, battery))
            } else if wakeCandidate {
                wakeEvents.append((date, battery, extractWakeReason(from: trimmed)))
            }
        }
        guard recognizedRecord else { return .failure(.unsupportedFormat) }
        sleepEvents.sort { $0.date < $1.date }
        wakeEvents.sort { $0.date < $1.date }
        let lastWakeReason = wakeEvents.last?.reason
        var sessions: [SleepSession] = []
        var wakeIndex = 0
        for sleep in sleepEvents {
            while wakeIndex < wakeEvents.count && wakeEvents[wakeIndex].date <= sleep.date { wakeIndex += 1 }
            let wake = wakeIndex < wakeEvents.count ? wakeEvents[wakeIndex] : nil
            sessions.append(SleepSession(
                sleepTime: sleep.date, wakeTime: wake?.date,
                batteryAtSleep: sleep.battery, batteryAtWake: wake?.battery, wakeReason: wake?.reason
            ))
            if wake != nil { wakeIndex += 1 }
        }
        return .success(SleepReadPayload(sessions: Array(sessions.suffix(5).reversed()), lastWakeReason: lastWakeReason))
    }

    static func parseUSBDevices(_ json: String) -> Result<[USBDevice], DiagnosticReadError> {
        guard let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
            return .failure(.malformedFormat)
        }
        guard let rawBuses = root["SPUSBDataType"] else { return .failure(.unsupportedFormat) }
        guard let buses = rawBuses as? [[String: Any]] else { return .failure(.malformedFormat) }
        var devices: [USBDevice] = []
        for bus in buses {
            guard collectUSBDevices(from: bus, isBus: true, into: &devices) else { return .failure(.malformedFormat) }
        }
        return .success(devices)
    }

    static func parseObservedSettings(_ output: String) -> Result<[ObservedSetting], DiagnosticReadError> {
        let keys = SleepSetting.allCases.flatMap(\.pmsetKeys)
        var values: [String: String] = [:]
        for line in output.components(separatedBy: .newlines) {
            let parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard let key = parts.first, keys.contains(key) else { continue }
            guard parts.count == 2, values[key] == nil,
                  parts[1].allSatisfy({ $0.isASCII && $0.isNumber }) else { return .failure(.malformedFormat) }
            values[key] = parts[1]
        }
        guard !values.isEmpty else { return .failure(.unsupportedFormat) }
        return .success(keys.map { ObservedSetting(key: $0, actualValue: values[$0]) })
    }

    // MARK: - Parser helpers

    private static func extractWakeReason(from line: String) -> String? {
        guard let range = line.range(of: "due to ") else { return nil }
        let reason = line[range.upperBound...].prefix(while: { $0 != "\t" }).trimmingCharacters(in: .whitespaces)
        return reason.isEmpty ? nil : reason
    }

    private static func collectUSBDevices(from node: [String: Any], isBus: Bool, into devices: inout [USBDevice]) -> Bool {
        guard let name = node["_name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        for key in ["manufacturer", "vendor_id", "bus_power_used"] where node[key] != nil {
            guard let value = node[key] as? String, !value.isEmpty else { return false }
        }
        let hasIdentity = node["manufacturer"] != nil || node["vendor_id"] != nil
        guard isBus || hasIdentity else { return false }
        if hasIdentity { devices.append(USBDevice(name: name, busPowerUsed: node["bus_power_used"] as? String)) }
        if let rawItems = node["_items"] {
            guard let items = rawItems as? [[String: Any]] else { return false }
            for item in items {
                guard collectUSBDevices(from: item, isBus: false, into: &devices) else { return false }
            }
        }
        return true
    }
}
