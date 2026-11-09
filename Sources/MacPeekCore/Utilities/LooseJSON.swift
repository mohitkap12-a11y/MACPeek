import Foundation

/// Tolerant reading of JSON printed by other tools (docker, podman, limactl, system_profiler, Ollama…), whose fields
/// vary between versions. A missing or differently typed field is nil, never a crash or a failed parse of the whole
/// document. Numbers printed as strings ("4", "12.5") are accepted where a number is expected.
public enum LooseJSON {
    public typealias Object = [String: Any]

    /// The whole text as one JSON value, or nil.
    public static func parse(_ text: String) -> Any? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    /// The text as an array of objects: a JSON array, a single object, or one object per line (`--format '{{json .}}'`).
    public static func objects(_ text: String) -> [Object] {
        if let whole = parse(text) {
            if let array = whole as? [Any] { return array.compactMap { $0 as? Object } }
            if let object = whole as? Object { return [object] }
        }
        return text.split(whereSeparator: \.isNewline).compactMap { line in parse(String(line)) as? Object }
    }

    public static func string(_ object: Object, _ key: String) -> String? {
        switch object[key] {
        case let value as String: return value
        case let value as NSNumber where !isBool(value): return value.stringValue
        default: return nil
        }
    }

    /// A non-empty string after trimming.
    public static func text(_ object: Object, _ key: String) -> String? {
        guard let value = string(object, key)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    public static func double(_ object: Object, _ key: String) -> Double? {
        switch object[key] {
        case let value as NSNumber where !isBool(value): return value.doubleValue
        case let value as String: return Double(value.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    public static func int(_ object: Object, _ key: String) -> Int? {
        guard let value = double(object, key), value.isFinite, abs(value) < 9e15 else { return nil }
        return Int(value)
    }

    public static func uint64(_ object: Object, _ key: String) -> UInt64? {
        guard let value = double(object, key), value.isFinite, value >= 0, value < 1.8e19 else { return nil }
        return UInt64(value)
    }

    public static func bool(_ object: Object, _ key: String) -> Bool? {
        switch object[key] {
        case let value as NSNumber: return value.boolValue
        case let value as String:
            switch value.lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return nil
            }
        default: return nil
        }
    }

    public static func object(_ object: Object, _ key: String) -> Object? { object[key] as? Object }

    public static func array(_ object: Object, _ key: String) -> [Object] { (object[key] as? [Any])?.compactMap { $0 as? Object } ?? [] }

    public static func strings(_ object: Object, _ key: String) -> [String] {
        if let values = object[key] as? [Any] { return values.compactMap { $0 as? String } }
        if let value = object[key] as? String { return [value] }
        return []
    }

    private static func isBool(_ number: NSNumber) -> Bool {
        #if canImport(Darwin)
        return CFGetTypeID(number) == CFBooleanGetTypeID()
        #else
        return false
        #endif
    }
}

/// Finds a command-line tool at a fixed list of well-known locations. MacPeek never searches the user's PATH or shell
/// configuration: a menu-bar app does not inherit it, and a fixed list keeps what runs predictable.
public struct ExecutableLocator: Sendable {
    public let candidates: [String]
    private let isExecutable: @Sendable (String) -> Bool

    public init(candidates: [String], isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) {
        self.candidates = candidates
        self.isExecutable = isExecutable
    }

    public func locate() -> String? { candidates.first(where: isExecutable) }

    /// Standard install locations for a tool: Homebrew on Apple silicon and Intel, then any extra paths. `~` is expanded
    /// to the current user's home folder.
    public static func standard(_ name: String, extra: [String] = []) -> ExecutableLocator {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)"] + extra
        return ExecutableLocator(candidates: paths.map { $0.hasPrefix("~/") ? home + $0.dropFirst() : $0 })
    }
}

/// Byte counts as other tools print them: "12.5MiB", "1.2GB", "512kB", "0B", "3.4 GiB". Binary units (KiB, MiB…)
/// are powers of 1024, decimal units (kB, MB…) powers of 1000.
public enum ByteSizeText {
    private static let pattern = NSRegularExpression.compile(#"^\s*([0-9]+(?:\.[0-9]+)?)\s*([KkMGTP]?i?)B?\s*$"#)

    public static func parse(_ text: String) -> UInt64? {
        guard let groups = pattern.groups(in: text), let number = groups[1].flatMap(Double.init) else { return nil }
        let unit = groups[2] ?? ""
        let binary = unit.hasSuffix("i")
        let base: Double = binary ? 1024 : 1000
        let exponent: Double
        switch unit.first.map({ Character($0.uppercased()) }) {
        case nil: exponent = 0
        case "K": exponent = 1
        case "M": exponent = 2
        case "G": exponent = 3
        case "T": exponent = 4
        case "P": exponent = 5
        default: return nil
        }
        let value = number * pow(base, exponent)
        guard value.isFinite, value >= 0, value < 1.8e19 else { return nil }
        return UInt64(value.rounded())
    }

    /// "12.5%" or "12.5" → 12.5.
    public static func percent(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: ""))
    }
}
