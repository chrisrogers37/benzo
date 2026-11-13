import Foundation

/// Parsed representation of `pmset -g` output
struct PMSetState {
    let values: [String: String]

    init(parsing output: String) {
        var parsed: [String: String] = [:]
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Lines look like: "hibernatemode        3"
            let parts = trimmed.split(separator: " ", maxSplits: 1)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                parsed[parts[0]] = parts[1]
            }
        }
        values = parsed
    }

    func value(for key: String) -> String? {
        values[key]
    }
}

/// The profile switches accepted by the exact-cell mutation transport.
enum PowerProfile: String, Codable, CaseIterable, Comparable {
    case ac, battery, ups

    var argument: String {
        switch self {
        case .ac: return "-c"
        case .battery: return "-b"
        case .ups: return "-u"
        }
    }

    var title: String {
        switch self {
        case .ac: return "AC Power"
        case .battery: return "Battery Power"
        case .ups: return "UPS Power"
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

enum ManagedKey: String, Codable, CaseIterable {
    case hibernatemode, standby, autopoweroff, powernap, tcpkeepalive, proximitywake, womp

    func isValid(_ value: Int) -> Bool {
        self == .hibernatemode ? [0, 3, 25].contains(value) : (value == 0 || value == 1)
    }
}

struct ManagedCell: Codable, Hashable, Comparable {
    let profile: PowerProfile
    let key: ManagedKey

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.profile != rhs.profile { return lhs.profile < rhs.profile }
        return ManagedKey.allCases.firstIndex(of: lhs.key)! < ManagedKey.allCases.firstIndex(of: rhs.key)!
    }
}

struct CellValue: Codable, Equatable {
    let cell: ManagedCell
    let value: Int
}

enum RecoveryEvidenceError: LocalizedError {
    case invalid(String)
    case receiptRequired(RecoveryJournal)

    var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        case .receiptRequired: return "Settings need a final recovery receipt. Retry verification before considering them Off."
        }
    }
}

/// Complete reported profiles and validated managed values, retaining the source capture.
struct ProfileSnapshot: Codable, Equatable {
    let raw: String
    let values: [CellValue]
    private let reportedProfiles: [PowerProfile]

    var profiles: [PowerProfile] { reportedProfiles }

    init(parsing output: String) throws {
        guard !output.isEmpty, output.utf8.count <= 65_536,
              !output.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw RecoveryEvidenceError.invalid("Settings capture is empty or exceeds the supported limit.")
        }
        let headings: [String: PowerProfile] = ["AC Power:": .ac, "Battery Power:": .battery, "UPS Power:": .ups]
        // These rows are reported by pmset but are outside Benzo's selected controls.
        let unmanaged: Set<String> = [
            "destroyfvkeyonstandby", "standbydelay", "standbydelayhigh", "standbydelaylow",
            "highstandbythreshold", "autopoweroffdelay", "sleep", "disksleep", "displaysleep",
            "ttyskeepawake", "lidwake", "acwake", "autorestart", "ring", "powerbutton",
            "networkoversleep", "halfdim", "disablesleep", "lessbright", "sms", "smsenable",
            "gpuswitch", "lowpowermode", "highpowermode", "powermode", "PrioritizeNetworkReachabilityOverSleep",
            "hibernatefile", "GPUSwitch", "Display Sleep Uses Dim", "Sleep On Power Button", "SleepServices"
        ]
        var seenProfiles = Set<PowerProfile>()
        var parsed: [ManagedCell: Int] = [:]
        var profile: PowerProfile?
        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if let next = headings[line] {
                guard seenProfiles.insert(next).inserted else {
                    throw RecoveryEvidenceError.invalid("Settings capture contains a duplicate power profile.")
                }
                profile = next
                continue
            }
            guard !line.contains(":"), let profile else {
                throw RecoveryEvidenceError.invalid("Settings capture contains an unknown or missing profile heading.")
            }
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard let first = parts.first else { continue }
            if let key = ManagedKey(rawValue: String(first)) {
                guard parts.count == 2, let number = Self.asciiInteger(String(parts[1])), key.isValid(number) else {
                    throw RecoveryEvidenceError.invalid("Settings capture contains an unsupported managed value.")
                }
                let cell = ManagedCell(profile: profile, key: key)
                guard parsed.updateValue(number, forKey: cell) == nil else {
                    throw RecoveryEvidenceError.invalid("Settings capture contains a duplicate managed setting.")
                }
            } else {
                let name = parts.dropLast().joined(separator: " ")
                guard parts.count >= 2, unmanaged.contains(name),
                      (Self.asciiInteger(String(parts.last!)) != nil ||
                       (name == "hibernatefile" && parts.count == 2 && parts.last!.hasPrefix("/"))) else {
                    throw RecoveryEvidenceError.invalid("Settings capture contains an unrecognized setting row.")
                }
            }
        }
        guard !seenProfiles.isEmpty else {
            throw RecoveryEvidenceError.invalid("Settings capture contains no power profiles.")
        }
        raw = output
        values = parsed.keys.sorted().map { CellValue(cell: $0, value: parsed[$0]!) }
        reportedProfiles = seenProfiles.sorted()
    }

    func value(for cell: ManagedCell) -> Int? { values.first(where: { $0.cell == cell })?.value }

    private static func asciiInteger(_ value: String) -> Int? {
        guard !value.isEmpty, value.utf8.count <= 19,
              value.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return nil }
        return Int(value)
    }

    private enum CodingKeys: String, CodingKey { case raw, values }

    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        let source = try fields.decode(String.self, forKey: .raw)
        let evidence = try fields.decode([CellValue].self, forKey: .values)
        try self.init(parsing: source)
        guard evidence == values else {
            throw RecoveryEvidenceError.invalid("Stored settings values do not match their original capture.")
        }
    }
}
