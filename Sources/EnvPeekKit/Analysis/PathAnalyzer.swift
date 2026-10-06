import Foundation

/// One entry of a PATH-style variable, with what can be said about it without running anything.
public struct PathEntry: Identifiable, Equatable, Sendable {
    public var id: Int { index }
    public let index: Int
    public let path: String
    /// Nil when existence was not checked.
    public let exists: Bool?
    /// The index of an earlier entry with the same path. Only the first one can ever be used.
    public let duplicateOf: Int?
    /// An empty entry means "the current directory", which is rarely intended.
    public let isEmpty: Bool
    public let isRelative: Bool

    public init(index: Int, path: String, exists: Bool?, duplicateOf: Int?, isEmpty: Bool, isRelative: Bool) {
        self.index = index
        self.path = path
        self.exists = exists
        self.duplicateOf = duplicateOf
        self.isEmpty = isEmpty
        self.isRelative = isRelative
    }

    public var notes: [String] {
        var notes: [String] = []
        if isEmpty { notes.append("Empty entry (means the current directory)") }
        else if isRelative { notes.append("Relative path") }
        if let duplicateOf { notes.append("Duplicate of entry \(duplicateOf + 1)") }
        if exists == false { notes.append("Does not exist") }
        return notes
    }
}

public enum PathAnalyzer {
    /// Relative entries depend on the working directory of whoever uses the variable, which is unknown here, so
    /// their existence is never checked (`exists` is nil) rather than answered for MacPeek's own directory.
    public static func analyze(_ value: String, directoryExists: (String) -> Bool) -> [PathEntry] {
        var firstSeen: [String: Int] = [:]
        return value.split(separator: ":", omittingEmptySubsequences: false).enumerated().map { index, part in
            let path = String(part)
            let empty = path.isEmpty
            let duplicate = empty ? nil : firstSeen[path]
            if !empty, firstSeen[path] == nil { firstSeen[path] = index }
            let relative = !empty && !path.hasPrefix("/") && !path.hasPrefix("~")
            return PathEntry(index: index, path: path, exists: (empty || relative) ? nil : directoryExists(path),
                             duplicateOf: duplicate, isEmpty: empty, isRelative: relative)
        }
    }

    /// Variables whose value is a colon-separated list worth showing entry by entry.
    public static func isPathLike(_ name: String) -> Bool {
        ["PATH", "MANPATH", "INFOPATH", "FPATH", "CDPATH", "DYLD_LIBRARY_PATH", "LD_LIBRARY_PATH", "PKG_CONFIG_PATH", "CLASSPATH"].contains(name.uppercased())
    }
}
