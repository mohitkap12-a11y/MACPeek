import Foundation

/// What StartupPeek takes from a launchd property list. The file is untrusted data: it is parsed, never executed, and
/// every value is type-checked before use.
public struct LaunchdDescription: Equatable, Sendable {
    public let label: String?
    public let program: String?
    public let programArguments: [String]
    public let runAtLoad: Bool
    public let keepAlive: Bool
    public let disabled: Bool
    public let hasOnDemandTriggers: Bool
    public let associatedBundleIdentifiers: [String]

    /// The executable launchd would run: `Program`, else the first element of `ProgramArguments`.
    public var executablePath: String? {
        if let program, !program.isEmpty { return program }
        return programArguments.first.flatMap { $0.isEmpty ? nil : $0 }
    }

    public var status: StartupStatus {
        if disabled { return .disabledInFile }
        if runAtLoad || keepAlive { return .startsAutomatically }
        if hasOnDemandTriggers { return .startsOnDemand }
        return .unknown
    }
}

public enum LaunchdPlistParser {
    /// Largest property list that is read. Real launchd files are a few kilobytes.
    public static let maxBytes = 1_000_000

    private static let triggerKeys = ["Sockets", "StartInterval", "StartCalendarInterval", "WatchPaths", "QueueDirectories",
                                      "StartOnMount", "MachServices", "LaunchEvents"]

    public static func parse(_ data: Data) throws -> LaunchdDescription {
        guard data.count <= maxBytes else { throw StartupPeekError.malformedPropertyList }
        let object: Any
        do {
            object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw StartupPeekError.malformedPropertyList
        }
        guard let dictionary = object as? [String: Any] else { throw StartupPeekError.malformedPropertyList }

        let arguments = (dictionary["ProgramArguments"] as? [Any])?.compactMap { $0 as? String } ?? []
        return LaunchdDescription(
            label: dictionary["Label"] as? String,
            program: dictionary["Program"] as? String,
            programArguments: arguments,
            runAtLoad: bool(dictionary["RunAtLoad"]),
            keepAlive: keepAlive(dictionary["KeepAlive"]),
            disabled: bool(dictionary["Disabled"]),
            hasOnDemandTriggers: triggerKeys.contains { dictionary[$0] != nil },
            associatedBundleIdentifiers: bundleIdentifiers(dictionary["AssociatedBundleIdentifiers"]))
    }

    private static func bool(_ value: Any?) -> Bool {
        (value as? Bool) ?? false
    }

    /// `KeepAlive` is either a boolean or a dictionary of conditions; a dictionary means "kept alive under conditions".
    private static func keepAlive(_ value: Any?) -> Bool {
        if let flag = value as? Bool { return flag }
        if let conditions = value as? [String: Any] { return !conditions.isEmpty }
        return false
    }

    private static func bundleIdentifiers(_ value: Any?) -> [String] {
        if let single = value as? String { return [single] }
        return (value as? [Any])?.compactMap { $0 as? String } ?? []
    }
}
