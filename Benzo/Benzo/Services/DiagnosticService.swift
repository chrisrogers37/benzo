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

    // MARK: - Sleep Sessions

    static func fetchSleepSessions(limit: Int = 5) -> [SleepSession] {
        guard let log = try? ShellExecutor.run("pmset -g log") else { return [] }

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

        // Pair sleep events with their subsequent wake events
        var sessions: [SleepSession] = []
        for sleep in sleepEvents.reversed() {
            let matchingWake = wakeEvents.first(where: { $0.date > sleep.date })
            sessions.append(SleepSession(
                sleepTime: sleep.date,
                wakeTime: matchingWake?.date,
                batteryAtSleep: sleep.battery,
                batteryAtWake: matchingWake?.battery,
                wakeReason: matchingWake?.reason
            ))
            if let wake = matchingWake {
                wakeEvents.removeAll(where: { $0.date == wake.date })
            }
            if sessions.count >= limit { break }
        }

        return sessions
    }

    // MARK: - Last Wake Reason

    static func fetchLastWakeReason() -> String? {
        guard let log = try? ShellExecutor.run("pmset -g log") else { return nil }

        // Search from the end for the most recent wake event
        let lines = log.components(separatedBy: .newlines).reversed()
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("Wake from") || trimmed.contains("\tWake\t") {
                return extractWakeReason(from: trimmed)
            }
        }
        return nil
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
        // Extract date from the beginning of the line (format: "2024-03-15 22:30:15 -0500")
        // The date portion is roughly the first 25 characters
        let components = line.split(separator: " ", maxSplits: 3)
        guard components.count >= 3 else { return nil }

        let dateString = "\(components[0]) \(components[1]) \(components[2])"
        guard let date = dateFormatter.date(from: dateString) else { return nil }

        // Extract battery charge from "Charge:XX%"
        var battery: Int?
        if let range = line.range(of: "Charge:") {
            let afterCharge = line[range.upperBound...]
            let digits = afterCharge.prefix(while: { $0.isNumber })
            battery = Int(digits)
        }

        return (date: date, battery: battery)
    }

    private static func extractWakeReason(from line: String) -> String? {
        // Look for "due to <reason>" pattern
        if let range = line.range(of: "due to ") {
            let afterDue = line[range.upperBound...]
            // Take until next whitespace cluster or end of meaningful text
            let reason = afterDue.prefix(while: { $0 != "\t" })
                .trimmingCharacters(in: .whitespaces)
            if !reason.isEmpty { return reason }
        }
        return nil
    }

    private static func collectUSBDevices(from dict: [String: Any], into devices: inout [USBDevice]) {
        // Skip root bus entries, only collect actual devices
        if let name = dict["_name"] as? String,
           !name.contains("Bus") || dict["manufacturer"] != nil {
            let power = dict["bus_power_used"] as? String
            if dict["manufacturer"] != nil || dict["vendor_id"] != nil {
                devices.append(USBDevice(name: name, busPowerUsed: power))
            }
        }

        // Recurse into child items
        if let items = dict["_items"] as? [[String: Any]] {
            for item in items {
                collectUSBDevices(from: item, into: &devices)
            }
        }
    }
}
