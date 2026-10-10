import Foundation
import MacPeekCore

public protocol MacOSUpdateChecking: Sendable {
    /// The updates macOS lists right now. An empty list means macOS said there is no new software.
    func list() async throws -> [MacOSUpdate]
}

public protocol SoftwareUpdateRecordReading: Sendable {
    /// Updates macOS's own record says it found, or nil when the record has none (which proves nothing either way).
    func read() -> MacOSUpdateReport?
}

/// Parses `softwareupdate --list`. The format has been stable for years but is not a documented API, so anything that is
/// neither a list of updates nor the "no new software" message fails as malformed instead of being read as "nothing to do".
///
///     * Label: macOS Sonoma 14.4.1-23E224
///         Title: macOS Sonoma 14.4.1, Version: 14.4.1, Size: 1234567KiB, Recommended: YES, Action: restart,
public enum SoftwareUpdateListParser {
    public static func parse(_ output: String) throws -> [MacOSUpdate] {
        let lines = output.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        var updates: [MacOSUpdate] = []
        var pendingLabel: String?
        for line in lines {
            if line.hasPrefix("* Label:") {
                if let label = pendingLabel { updates.append(MacOSUpdate(name: label)) }
                pendingLabel = String(line.dropFirst("* Label:".count)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("Title:"), let label = pendingLabel {
                updates.append(update(label: label, details: line))
                pendingLabel = nil
            }
        }
        if let label = pendingLabel, !label.isEmpty { updates.append(MacOSUpdate(name: label)) }
        if !updates.isEmpty { return Array(updates.prefix(50)) }
        if lines.contains(where: { $0.localizedCaseInsensitiveContains("No new software available") }) { return [] }
        throw UpdatePeekError.malformedData
    }

    private static func update(label: String, details: String) -> MacOSUpdate {
        // "Title" can contain a comma, so it ends at ", Version:" when that is present.
        let titleEnd = details.range(of: ", Version:")
        let title = field("Title", in: details, endingAt: titleEnd?.lowerBound)
        let version = field("Version", in: details)
        let recommended = field("Recommended", in: details).map { $0.uppercased() == "YES" }
        let restart = field("Action", in: details).map { $0.lowercased() == "restart" }
        return MacOSUpdate(name: (title?.isEmpty == false ? title : nil) ?? label, version: version,
                           isRecommended: recommended, requiresRestart: restart)
    }

    private static func field(_ key: String, in line: String, endingAt end: String.Index? = nil) -> String? {
        guard let start = line.range(of: "\(key): ") else { return nil }
        let rest = line[start.upperBound...]
        let stop = end.map { min($0, rest.endIndex) } ?? rest.range(of: ", ")?.lowerBound ?? rest.endIndex
        guard stop >= rest.startIndex else { return nil }
        let value = rest[rest.startIndex..<stop].trimmingCharacters(in: CharacterSet(charactersIn: ", ").union(.whitespaces))
        return value.isEmpty ? nil : String(value.prefix(200))
    }
}

/// Runs `softwareupdate --list`: a fixed executable and argument, no shell. It asks Apple's update servers, so it makes a
/// network request and only runs when the user presses Check now. It lists; it never downloads or installs.
public struct SoftwareUpdateChecker: MacOSUpdateChecking {
    public static let failureMessage = "macOS could not check for updates. Check your network connection and try again."
    static let executable = "/usr/sbin/softwareupdate"
    static let arguments = ["--list"]

    private let runner: CommandRunning

    public init(runner: CommandRunning = ShellCommand(timeout: 120)) {
        self.runner = runner
    }

    public func list() async throws -> [MacOSUpdate] {
        let output: CommandOutput
        do {
            output = try await runner.run(Self.executable, Self.arguments)
        } catch let error as CommandError {
            throw UpdatePeekError.operationFailed(error.localizedDescription)
        }
        guard output.status == 0 else { throw UpdatePeekError.operationFailed(Self.failureMessage) }
        // The tool writes its progress lines to stderr and the list to stdout; read both.
        do {
            return try SoftwareUpdateListParser.parse(output.stdout + "\n" + output.stderr)
        } catch UpdatePeekError.malformedData {
            throw UpdatePeekError.operationFailed("macOS's answer could not be understood.")
        }
    }
}

/// Reads the updates macOS's own Software Update record lists (`RecommendedUpdates` in
/// /Library/Preferences/com.apple.SoftwareUpdate.plist, world-readable). Local and read-only: no command, no request. This
/// is what macOS found on its last background check, so it can be stale and an empty record proves nothing; the screen
/// says so. Property list contents are untrusted: size-capped, type-checked, never executed.
public struct PreferencesSoftwareUpdateRecord: SoftwareUpdateRecordReading {
    private static let maxBytes = 2_000_000
    private let path: String

    public init(path: String = "/Library/Preferences/com.apple.SoftwareUpdate.plist") {
        self.path = path
    }

    public func read() -> MacOSUpdateReport? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        // Reads at most maxBytes + 1, so an oversized file is rejected without loading it.
        let data = handle.readData(ofLength: Self.maxBytes + 1)
        guard data.count <= Self.maxBytes,
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let entries = plist["RecommendedUpdates"] as? [[String: Any]] else { return nil }
        let updates: [MacOSUpdate] = entries.prefix(50).compactMap { entry in
            let name = (entry["Display Name"] as? String) ?? (entry["Identifier"] as? String) ?? ""
            guard !name.isEmpty else { return nil }
            return MacOSUpdate(name: String(name.prefix(200)), version: (entry["Display Version"] as? String).map { String($0.prefix(50)) })
        }
        guard !updates.isEmpty else { return nil }
        let date = (plist["LastFullSuccessfulDate"] as? Date) ?? (plist["LastSuccessfulDate"] as? Date)
        return MacOSUpdateReport(updates: updates, source: .macOSRecord, checkedAt: date)
    }
}
