import Foundation

/// Parses `brew outdated --json=v2`. Homebrew documents this JSON for scripts; it is still treated as untrusted input:
/// anything that is not the expected shape fails as malformed rather than being half-read.
public enum HomebrewParser {
    private struct Document: Decodable {
        let formulae: [Entry]?
        let casks: [Entry]?
    }

    private struct Entry: Decodable {
        let name: String
        let installedVersions: [String]
        let currentVersion: String

        enum CodingKeys: String, CodingKey {
            case name
            case installedVersions = "installed_versions"
            case currentVersion = "current_version"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            currentVersion = try container.decode(String.self, forKey: .currentVersion)
            // Casks have reported installed_versions as a string, formulae as an array.
            if let many = try? container.decode([String].self, forKey: .installedVersions) {
                installedVersions = many
            } else if let one = try? container.decode(String.self, forKey: .installedVersions) {
                installedVersions = [one]
            } else {
                installedVersions = []
            }
        }
    }

    public static func parse(_ json: String) throws -> [OutdatedPackage] {
        guard let data = json.data(using: .utf8),
              let document = try? JSONDecoder().decode(Document.self, from: data),
              document.formulae != nil || document.casks != nil else { throw UpdatePeekError.malformedData }
        let formulae = (document.formulae ?? []).map {
            OutdatedPackage(name: $0.name, kind: .formula, installedVersions: $0.installedVersions, currentVersion: $0.currentVersion)
        }
        let casks = (document.casks ?? []).map {
            OutdatedPackage(name: $0.name, kind: .cask, installedVersions: $0.installedVersions, currentVersion: $0.currentVersion)
        }
        return (formulae + casks).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
