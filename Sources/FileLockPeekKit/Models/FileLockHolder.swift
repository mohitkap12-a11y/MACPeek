import Foundation

public enum OpenAccess: String, Hashable, Sendable {
    case read, write, readWrite
    /// lsof could not tell (access mode field blank or "-").
    case unknown

    public var label: String {
        switch self {
        case .read: return "read"
        case .write: return "write"
        case .readWrite: return "read/write"
        case .unknown: return "access unknown"
        }
    }
}

/// How a process holds a path, derived from lsof's file-descriptor column.
public enum HoldKind: Hashable, Sendable {
    /// An ordinary open file descriptor.
    case open(OpenAccess)
    /// The process's current working directory (blocks ejecting a volume or deleting a folder).
    case workingDirectory
    /// The path is the process's executable (program text).
    case executable
    /// The path is memory-mapped (for example a loaded library).
    case memoryMapped
    /// Anything else lsof reports; carries the raw descriptor.
    case other(String)

    public var label: String {
        switch self {
        case .open(let access): return "Open (\(access.label))"
        case .workingDirectory: return "Working directory"
        case .executable: return "Executable"
        case .memoryMapped: return "Memory-mapped"
        case .other(let raw): return raw
        }
    }

    /// Lower sorts first: real opens and locks matter most, memory maps least.
    var priority: Int {
        switch self {
        case .open: return 0
        case .workingDirectory: return 1
        case .executable: return 2
        case .memoryMapped: return 3
        case .other: return 4
        }
    }
}

/// One open file (or directory) belonging to a holder.
public struct OpenFile: Hashable, Sendable {
    public let path: String
    /// The raw lsof descriptor, e.g. `3r`, `cwd`, `txt`, `5uW`.
    public let descriptor: String
    public let kind: HoldKind
    /// Human description of an advisory lock held on the file, if any (e.g. "write lock (whole file)").
    public let lock: String?
    /// lsof's file type (REG, DIR, …) when reported.
    public let fileType: String?

    public init(path: String, descriptor: String, kind: HoldKind, lock: String? = nil, fileType: String? = nil) {
        self.path = path
        self.descriptor = descriptor
        self.kind = kind
        self.lock = lock
        self.fileType = fileType
    }
}

/// A process that holds the queried path, with every file it holds under that path.
public struct FileLockHolder: Identifiable, Hashable, Sendable {
    public var id: Int { pid }
    public let pid: Int
    public let processName: String
    public let user: String?
    public let files: [OpenFile]
    /// Process start time, used with the PID to detect PID reuse before any termination.
    public let startTime: TimeInterval?

    public init(pid: Int, processName: String, user: String? = nil, files: [OpenFile], startTime: TimeInterval? = nil) {
        self.pid = pid
        self.processName = processName
        self.user = user
        self.files = files
        self.startTime = startTime
    }

    public func withStartTime(_ startTime: TimeInterval?) -> FileLockHolder {
        FileLockHolder(pid: pid, processName: processName, user: user, files: files, startTime: startTime)
    }

    /// The most significant way this process holds the path (used for sorting and the row badge).
    public var primaryKind: HoldKind {
        files.map(\.kind).min { $0.priority < $1.priority } ?? .other("unknown")
    }

    public var hasLock: Bool { files.contains { $0.lock != nil } }
}
