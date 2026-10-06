import Foundation
import MacPeekCore

/// Parses `lsof -F` field output into `PortInfo` values. Pure and deterministic.
///
/// Expected field set (see `LsofPortDiscovery`): `p` pid, `c` command, `L` login,
/// `f` fd, `t` type, `P` protocol, `n` name, `T` TCP info (`TST=LISTEN`).
public enum PortParser {
    public static func parse(_ output: String) -> [PortInfo] {
        var results: [PortInfo] = []
        var seen = Set<String>()

        var pid: Int?
        var command = ""
        var user: String?
        var inFile = false
        var proto: String?
        var name: String?
        var state: String?

        func flush() {
            defer { inFile = false; proto = nil; name = nil; state = nil }
            guard inFile, let pid, let name, let proto,
                  let protocolType = PortProtocol(rawValue: proto.uppercased()),
                  !name.contains("->"),
                  let endpoint = parseEndpoint(name)
            else { return }

            let portState = state.map(PortState.init(lsofValue:))
            if protocolType == .tcp, let portState, portState != .listen { return }

            let info = PortInfo(
                port: endpoint.port,
                protocolType: protocolType,
                address: endpoint.address,
                processName: command.isEmpty ? "unknown" : command,
                pid: pid,
                user: user,
                state: portState
            )
            if seen.insert(info.id).inserted { results.append(info) }
        }

        for rawLine in output.split(whereSeparator: \.isNewline) {
            guard let tag = rawLine.first else { continue }
            let value = String(rawLine.dropFirst())
            switch tag {
            case "p":
                flush()
                pid = Int(value)
                command = ""
                user = nil
            case "c": command = unescape(value)
            case "L": user = value.isEmpty ? nil : value
            case "f": flush(); inFile = true
            case "P": proto = value
            case "n": name = value
            case "T": if value.hasPrefix("ST=") { state = String(value.dropFirst(3)) }
            default: break
            }
        }
        flush()

        return results.sorted { ($0.port, $0.pid, $0.address) < ($1.port, $1.pid, $1.address) }
    }

    /// Splits `127.0.0.1:3000`, `*:3000`, `[::1]:3000` into address and port.
    /// Returns nil for unbound/unparseable names such as `*:*`.
    static func parseEndpoint(_ name: String) -> (address: String, port: Int)? {
        guard let colon = name.lastIndex(of: ":"),
              let port = Int(name[name.index(after: colon)...]),
              (1...65535).contains(port)
        else { return nil }
        var host = String(name[..<colon])
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        guard !host.isEmpty else { return nil }
        return (host, port)
    }

    /// lsof escapes some bytes in command names as `\xNN`.
    static func unescape(_ value: String) -> String { LsofEscape.decode(value) }
}
