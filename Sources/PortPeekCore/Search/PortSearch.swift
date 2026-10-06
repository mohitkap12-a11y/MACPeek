import Foundation

/// Instant, local, case-insensitive filtering. Every whitespace-separated token must match
/// at least one of: port, PID, process name, address, protocol.
public enum PortSearch {
    public static func filter(_ ports: [PortInfo], query: String) -> [PortInfo] {
        let tokens = query
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !tokens.isEmpty else { return ports }

        let matches = ports.filter { port in
            tokens.allSatisfy { matches(port, token: $0) }
        }
        // Exact port / PID hits first; stable otherwise.
        let first = tokens[0]
        func rank(_ p: PortInfo) -> Int {
            if String(p.port) == first { return 0 }
            if String(p.pid) == first { return 1 }
            return 2
        }
        return matches.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }

    static func matches(_ port: PortInfo, token: String) -> Bool {
        String(port.port).contains(token)
            || String(port.pid).contains(token)
            || port.processName.lowercased().contains(token)
            || port.address.lowercased().contains(token)
            || port.protocolType.rawValue.lowercased().contains(token)
    }
}
