import Foundation

public enum ProcessSort: String, CaseIterable, Sendable {
    case name = "Name"
    case cpu = "CPU"
    case memory = "Memory"
    case pid = "PID"
}

public enum ProcessSearch {
    /// Every whitespace-separated word must match the name, PID, user or command name (case-insensitive).
    public static func filter(_ entries: [ProcessEntry], query: String, ownedBy uid: Int?, sort: ProcessSort) -> [ProcessEntry] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        let matched = entries.filter { entry in
            if let uid, !entry.isOwned(by: uid) { return false }
            guard !words.isEmpty else { return true }
            let haystack = "\(entry.name) \(entry.pid) \(entry.user) \(entry.executable)".lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
        switch sort {
        case .name: return matched.sorted { ($0.name.lowercased(), $0.pid) < ($1.name.lowercased(), $1.pid) }
        case .cpu: return matched.sorted { ($0.cpuPercent, $1.pid) > ($1.cpuPercent, $0.pid) }
        case .memory: return matched.sorted { ($0.residentKB, $1.pid) > ($1.residentKB, $0.pid) }
        case .pid: return matched.sorted { $0.pid < $1.pid }
        }
    }
}
