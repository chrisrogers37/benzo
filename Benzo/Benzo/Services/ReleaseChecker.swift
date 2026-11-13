import Foundation

enum ReleaseCheckResult: Equatable {
    case current(version: String)
    case available(version: String, page: URL)
    case ahead
}

enum ReleaseCheckError: Error {
    case unknownVersion
    case unavailable
}

/// Metadata only. No live transport default, artifact download or recovery dependency.
struct ReleaseChecker {
    static let releasesURL = URL(string: "https://github.com/chrisrogers37/benzo/releases")!
    static let endpoint = URL(string: "https://api.github.com/repos/chrisrogers37/benzo/releases/latest")!
    static let maximumBytes = 1_048_576
    static let timeout: TimeInterval = 15

    let load: (URLRequest) async throws -> (Data, HTTPURLResponse)

    func check(installed: AppVersion) async throws -> ReleaseCheckResult {
        guard let local = installed.stableVersion else { throw ReleaseCheckError.unknownVersion }
        var request = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: Self.timeout)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Benzo-Update-Check", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await load(request)
        try Task.checkCancellation()
        guard response.statusCode == 200, response.url == Self.endpoint,
              data.count <= Self.maximumBytes,
              let release = try? JSONDecoder().decode(Release.self, from: data),
              !release.draft, !release.prerelease,
              let published = release.published_at,
              ISO8601DateFormatter().date(from: published) != nil,
              release.tag_name.first == "v",
              let latest = StableVersion(String(release.tag_name.dropFirst())),
              release.assets.contains(where: {
                  $0.name == "Benzo-\(latest).dmg" && $0.state == "uploaded" && $0.size > 0
              }) else { throw ReleaseCheckError.unavailable }

        if latest > local {
            // Only a validated numeric tag enters a fixed repository URL. Ignore html_url/body.
            let page = Self.releasesURL.appendingPathComponent("tag").appendingPathComponent("v\(latest)")
            return .available(version: latest.description, page: page)
        }
        return latest == local ? .current(version: latest.description) : .ahead
    }

    /// Used by the live byte stream and injected streams; stops before buffering excess data.
    static func collect<Bytes: AsyncSequence>(_ bytes: Bytes) async throws -> Data where Bytes.Element == UInt8 {
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumBytes else { throw ReleaseCheckError.unavailable }
            data.append(byte)
        }
        return data
    }

    private struct Release: Decodable {
        let tag_name: String
        let draft: Bool
        let prerelease: Bool
        let published_at: String?
        let assets: [Asset]
    }

    private struct Asset: Decodable {
        let name: String
        let state: String
        let size: Int
    }
}
