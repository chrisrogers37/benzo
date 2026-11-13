import Foundation

struct AppVersion {
    let shortVersion: String?
    let buildVersion: String?

    init(shortVersion: String?, buildVersion: String?) {
        self.shortVersion = shortVersion
        self.buildVersion = buildVersion
    }

    init(bundle: Bundle) {
        self.init(shortVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                  buildVersion: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
    }

    var stableVersion: StableVersion? { shortVersion.flatMap(StableVersion.init) }
    var display: String { stableVersion.map { "v\($0.description)" } ?? "Version unknown" }
}

/// Deliberately stable-only. No suffixes, coercion or lexicographic comparison.
struct StableVersion: Comparable, CustomStringConvertible {
    private let components: [Int]

    init?(_ value: String) {
        guard value.utf8.count <= 64 else { return nil }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.utf8.allSatisfy({ (48...57).contains($0) }),
                  part.count == 1 || part.first != "0", let number = Int(part) else { return nil }
            numbers.append(number)
        }
        components = numbers
    }

    var description: String { components.map(String.init).joined(separator: ".") }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }
}
