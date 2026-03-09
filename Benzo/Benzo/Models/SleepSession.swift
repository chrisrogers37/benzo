import Foundation

struct SleepSession: Identifiable {
    let id = UUID()
    let sleepTime: Date
    let wakeTime: Date?
    let batteryAtSleep: Int?
    let batteryAtWake: Int?
    let wakeReason: String?

    var duration: TimeInterval? {
        guard let wakeTime else { return nil }
        return wakeTime.timeIntervalSince(sleepTime)
    }

    var batteryDelta: Int? {
        guard let s = batteryAtSleep, let w = batteryAtWake else { return nil }
        return w - s
    }

    var formattedDuration: String {
        guard let duration else { return "In progress" }
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    var humanWakeReason: String {
        guard let reason = wakeReason else { return "Unknown" }
        if reason.contains("LidOpen") || reason.contains("Lid Open") { return "Lid Opened" }
        if reason.contains("PowerButton") || reason.contains("User") { return "Power Button" }
        if reason.contains("OHC") || reason.contains("EHC") || reason.contains("XHC") || reason.contains("USB") { return "USB Device" }
        if reason.contains("WOL") || reason.contains("Network") { return "Network (WoL)" }
        if reason.contains("RTC") || reason.contains("Alarm") { return "Scheduled Wake" }
        if reason.contains("Notification") { return "Push Notification" }
        if reason.contains("UserActivity") { return "User Activity" }
        if reason.contains("SleepService") { return "Sleep Service" }
        return reason
    }
}
