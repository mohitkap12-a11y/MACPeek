import Foundation

/// One row of `ps -axo pid,ppid,uid,user,state,lstart,etime,%cpu,rss,comm`.
public struct ProcessEntry: Identifiable, Equatable, Sendable {
    public var id: Int { pid }
    public let pid: Int
    public let ppid: Int
    public let uid: Int
    public let user: String
    /// The raw `ps` state field, e.g. `Ss`, `S+`, `R`.
    public let state: String
    public let startTime: Date?
    /// `ps` elapsed time as printed (`[[dd-]hh:]mm:ss`).
    public let elapsed: String
    /// CPU percentage as `ps` reports it: a decaying average, not an instantaneous reading.
    public let cpuPercent: Double
    public let residentKB: Int
    /// The executable path as `ps` prints it (`comm`). It can contain spaces.
    public let executable: String

    public init(pid: Int, ppid: Int, uid: Int, user: String, state: String, startTime: Date?, elapsed: String,
                cpuPercent: Double, residentKB: Int, executable: String) {
        self.pid = pid
        self.ppid = ppid
        self.uid = uid
        self.user = user
        self.state = state
        self.startTime = startTime
        self.elapsed = elapsed
        self.cpuPercent = cpuPercent
        self.residentKB = residentKB
        self.executable = executable
    }

    /// The last path component (`/Applications/Foo.app/Contents/MacOS/Foo` → `Foo`; `-zsh` stays `-zsh`).
    public var name: String {
        let last = executable.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? executable
        return last.isEmpty ? executable : last
    }

    public func isOwned(by currentUID: Int) -> Bool { uid == currentUID }

    /// Plain-language meaning of the first `ps` state letter. Anything unknown is shown as macOS wrote it.
    public var stateLabel: String {
        switch state.first {
        case "R": return "Running"
        case "S": return "Sleeping"
        case "I": return "Idle"
        case "U": return "Waiting on I/O"
        case "T": return "Stopped"
        case "Z": return "Zombie"
        default: return state
        }
    }

    public var memoryLabel: String { ByteCountLabel.kilobytes(residentKB) }
    public var elapsedLabel: String { ElapsedTime.label(elapsed) }
}

public enum ByteCountLabel {
    /// 4880 → "4.8 MB"; 24_000 → "23 MB"; 1_500_000 → "1.4 GB".
    public static func kilobytes(_ kb: Int) -> String {
        let value = Double(kb)
        if value >= 1_048_576 { return String(format: "%.1f GB", value / 1_048_576) }
        if value >= 1024 { return value >= 10_240 ? String(format: "%.0f MB", value / 1024) : String(format: "%.1f MB", value / 1024) }
        return "\(kb) KB"
    }
}

public enum ElapsedTime {
    /// `01-05:36:20` → "1d 5h"; `02:48:04` → "2h 48m"; `03:26` → "3m 26s".
    public static func label(_ raw: String) -> String {
        var days = 0
        var rest = Substring(raw)
        if let dash = rest.firstIndex(of: "-") {
            days = Int(rest[rest.startIndex..<dash]) ?? 0
            rest = rest[rest.index(after: dash)...]
        }
        let parts = rest.split(separator: ":").compactMap { Int($0) }
        guard !parts.isEmpty, parts.count <= 3 else { return raw }
        let hms: (Int, Int, Int)
        switch parts.count {
        case 3: hms = (parts[0], parts[1], parts[2])
        case 2: hms = (0, parts[0], parts[1])
        default: hms = (0, 0, parts[0])
        }
        let (hours, minutes, seconds) = hms
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(seconds)s" }
        return "\(seconds)s"
    }
}

public struct ProcessSnapshot: Equatable, Sendable {
    public let entries: [ProcessEntry]
    private let byPID: [Int: ProcessEntry]

    public init(entries: [ProcessEntry]) {
        self.entries = entries
        self.byPID = Dictionary(entries.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public func entry(pid: Int) -> ProcessEntry? { byPID[pid] }

    public func parent(of entry: ProcessEntry) -> ProcessEntry? {
        entry.ppid == entry.pid ? nil : byPID[entry.ppid]
    }

    public func children(of pid: Int) -> [ProcessEntry] {
        entries.filter { $0.ppid == pid && $0.pid != pid }.sorted { $0.pid < $1.pid }
    }

    /// Parent chain from the immediate parent up to the root (cycle-safe).
    public func ancestors(of entry: ProcessEntry) -> [ProcessEntry] {
        var chain: [ProcessEntry] = []
        var seen: Set<Int> = [entry.pid]
        var current = entry
        while let next = parent(of: current), !seen.contains(next.pid) {
            chain.append(next)
            seen.insert(next.pid)
            current = next
        }
        return chain
    }
}
