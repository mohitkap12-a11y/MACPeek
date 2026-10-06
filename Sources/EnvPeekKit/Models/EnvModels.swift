import Foundation

public struct EnvVariable: Identifiable, Equatable, Sendable {
    /// Unique within one environment even when a process lists the same name twice: the first keeps the bare
    /// name, later copies are `NAME#1`, `NAME#2`… Reveal state and row identity are keyed on this, never on the name.
    public var id: String { occurrence == 0 ? name : "\(name)#\(occurrence)" }
    public let name: String
    public let value: String
    /// 0 for the first appearance of the name in the environment, 1 for the second, and so on.
    public let occurrence: Int

    public init(name: String, value: String, occurrence: Int = 0) {
        self.name = name
        self.value = value
        self.occurrence = occurrence
    }

    /// `NAME=value`, for pasting into a shell or a bug report.
    public var assignment: String { "\(name)=\(value)" }

    /// Names that usually hold credentials. Their values are hidden until the user reveals them. This is a
    /// convenience heuristic, not a guarantee: any value can be sensitive.
    public var isSensitive: Bool { Self.looksSensitive(name) }

    public static func looksSensitive(_ name: String) -> Bool {
        let upper = name.uppercased()
        let fragments = ["TOKEN", "SECRET", "PASSWORD", "PASSWD", "CREDENTIAL", "PRIVATE", "COOKIE", "APIKEY", "API_KEY", "ACCESS_KEY"]
        if fragments.contains(where: { upper.contains($0) }) { return true }
        return upper.hasSuffix("_KEY") || upper.hasSuffix("_PASS") || upper == "PASS" || upper == "KEY"
    }
}

/// Where a set of variables came from. The label is always shown next to the values, so a per-process value is
/// never presented as global.
public enum EnvSource: Equatable, Sendable {
    case macPeek
    case process(pid: Int, name: String?)

    public var label: String {
        switch self {
        case .macPeek: return "MacPeek's own environment"
        case .process(let pid, let name):
            let prefix = name.map { $0 + " " } ?? ""
            return "Process " + prefix + "(PID \(pid))"
        }
    }

    public var caveat: String? {
        switch self {
        case .macPeek:
            return "This is the environment MacPeek was launched with. An app started from Finder or at login usually sees far fewer variables than your terminal does."
        case .process:
            return nil
        }
    }
}

public struct ProcessArguments: Equatable, Sendable {
    public let executable: String?
    public let arguments: [String]
    public let environment: [EnvVariable]

    public init(executable: String?, arguments: [String], environment: [EnvVariable]) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
    }
}

public enum EnvError: Error, Equatable, LocalizedError {
    case noSuchProcess
    case notPermitted
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .noSuchProcess: return "That process is not running."
        case .notPermitted: return "macOS does not let MacPeek read this process's environment. Only processes owned by your user can be read."
        case .unavailable(let detail): return detail
        }
    }
}
