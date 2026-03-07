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
