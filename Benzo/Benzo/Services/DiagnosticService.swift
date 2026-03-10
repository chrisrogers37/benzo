import Foundation

struct SettingVerification: Identifiable {
    let id = UUID()
    let setting: SleepSetting
    let key: String
    let expectedValue: String
    let actualValue: String
    let matches: Bool
}

enum DiagnosticService {

    // MARK: - Sleep Data (single log parse)

    static func fetchSleepData(limit: Int = 5) -> (sessions: [SleepSession], lastWakeReason: String?) {
        guard let log = try? ShellExecutor.run("pmset -g log") else { return ([], nil) }

        var sleepEvents: [(date: Date, battery: Int?)] = []
        var wakeEvents: [(date: Date, battery: Int?, reason: String?)] = []

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"

        for line in log.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.contains("Entering Sleep state") || (trimmed.contains("\tSleep\t") && !trimmed.contains("Back to")) {
                if let parsed = parsePMSetLogLine(trimmed, dateFormatter: dateFormatter) {
                    sleepEvents.append((date: parsed.date, battery: parsed.battery))
                }
            } else if trimmed.contains("Wake from") || trimmed.contains("\tWake\t") {
                if let parsed = parsePMSetLogLine(trimmed, dateFormatter: dateFormatter) {
                    let reason = extractWakeReason(from: trimmed)
                    wakeEvents.append((date: parsed.date, battery: parsed.battery, reason: reason))
                }
            }
        }

        // Extract last wake reason before pairing consumes events
        let lastWakeReason = wakeEvents.last?.reason

        // Pair sleep events with subsequent wake events chronologically
        // Both lists are already in chronological order from the log
        var sessions: [SleepSession] = []
        var wakeIndex = 0
        for sleep in sleepEvents {
            // Advance wake index past any wake events before this sleep
            while wakeIndex < wakeEvents.count && wakeEvents[wakeIndex].date <= sleep.date {
                wakeIndex += 1
            }
            let matchingWake = wakeIndex < wakeEvents.count ? wakeEvents[wakeIndex] : nil
            sessions.append(SleepSession(
                sleepTime: sleep.date,
                wakeTime: matchingWake?.date,
                batteryAtSleep: sleep.battery,
                batteryAtWake: matchingWake?.battery,
                wakeReason: matchingWake?.reason
            ))
            if matchingWake != nil {
                wakeIndex += 1
            }
        }

        // Return most recent sessions first, limited to requested count
        let recentSessions = Array(sessions.suffix(limit).reversed())
        return (recentSessions, lastWakeReason)
    }

    // MARK: - USB Devices

    static func fetchUSBDevices() -> [USBDevice] {
        guard let json = try? ShellExecutor.run("system_profiler SPUSBDataType -json") else { return [] }
        guard let data = json.data(using: .utf8) else { return [] }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let buses = root["SPUSBDataType"] as? [[String: Any]] else {
            return []
        }

        var devices: [USBDevice] = []
        for bus in buses {
            collectUSBDevices(from: bus, into: &devices)
        }
        return devices
    }

    // MARK: - Settings Verification

    static func verifySettings(settingStates: [SleepSetting: Bool], isActive: Bool) -> [SettingVerification] {
        guard let state = try? PMSetService.readCurrentState() else { return [] }

        var verifications: [SettingVerification] = []
        for setting in SleepSetting.allCases {
            let enabled = settingStates[setting] ?? setting.defaultEnabled
            for (key, targetValue) in setting.pmsetCommands {
                let actual = state.value(for: key) ?? "N/A"
                let expected = (isActive && enabled) ? targetValue : actual
                verifications.append(SettingVerification(
                    setting: setting,
                    key: key,
                    expectedValue: expected,
                    actualValue: actual,
                    matches: !isActive || !enabled || actual == targetValue
                ))
            }
        }
        return verifications
    }

    // MARK: - Private

    private static func parsePMSetLogLine(_ line: String, dateFormatter: DateFormatter) -> (date: Date, battery: Int?)? {
        let components = line.split(separator: " ", maxSplits: 3)
        guard components.count >= 3 else { return nil }

        let dateString = "\(components[0]) \(components[1]) \(components[2])"
        guard let date = dateFormatter.date(from: dateString) else { return nil }

        var battery: Int?
        if let range = line.range(of: "Charge:") {
            let afterCharge = line[range.upperBound...]
            let digits = afterCharge.prefix(while: { $0.isNumber })
            battery = Int(digits)
        }

        return (date: date, battery: battery)
    }

    private static func extractWakeReason(from line: String) -> String? {
        if let range = line.range(of: "due to ") {
            let afterDue = line[range.upperBound...]
            let reason = afterDue.prefix(while: { $0 != "\t" })
                .trimmingCharacters(in: .whitespaces)
            if !reason.isEmpty { return reason }
        }
        return nil
    }

    private static func collectUSBDevices(from dict: [String: Any], into devices: inout [USBDevice]) {
        if let name = dict["_name"] as? String {
            let hasIdentity = dict["manufacturer"] != nil || dict["vendor_id"] != nil
            if hasIdentity {
                let power = dict["bus_power_used"] as? String
                devices.append(USBDevice(name: name, busPowerUsed: power))
            }
        }

        if let items = dict["_items"] as? [[String: Any]] {
            for item in items {
                collectUSBDevices(from: item, into: &devices)
            }
        }
    }
}
