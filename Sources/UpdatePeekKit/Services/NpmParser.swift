import Foundation

/// Parses `npm outdated --global --json`: an object keyed by package name, each value with `current`, `wanted` and
/// `latest`. Treated as untrusted input: anything that is not the expected shape fails rather than being half-read.
/// With `--json`, npm reports its own failures (for example no network) as `{"error": {"code", "summary", "detail"}}`,
/// which is recognised and reported as a failure, never shown as a package.
public enum NpmParser {
    public static let failureMessage = "npm could not check for outdated packages. Check your network connection and try again."

    private struct Entry: Decodable {
        let current: String?
        let wanted: String?
        let latest: String?
        /// Present on npm's own error object, never on a package entry.
        let summary: String?
    }

    /// One package entry, or an array of them (npm may list a package once per location).
    private struct Item: Decodable {
        let entry: Entry?

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let one = try? container.decode(Entry.self) {
                entry = one
            } else if let many = try? container.decode([Entry].self) {
                entry = many.first
            } else {
                entry = nil
            }
        }
    }

    public static func parse(_ json: String) throws -> [OutdatedPackage] {
        guard let data = json.data(using: .utf8),
              let items = try? JSONDecoder().decode([String: Item].self, from: data) else { throw UpdatePeekError.malformedData }
        if let error = items["error"]?.entry, error.summary != nil, error.latest == nil {
            throw UpdatePeekError.operationFailed(failureMessage)
        }
        var packages: [OutdatedPackage] = []
        for (name, item) in items {
            guard let entry = item.entry, let latest = entry.latest, !latest.isEmpty, !name.isEmpty else {
                throw UpdatePeekError.malformedData
            }
            packages.append(OutdatedPackage(name: name, kind: .npm, installedVersions: entry.current.map { [$0] } ?? [],
                                            currentVersion: latest))
        }
        return packages.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
