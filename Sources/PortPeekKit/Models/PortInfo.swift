import Foundation

public enum PortProtocol: String, Hashable, Sendable, CaseIterable {
    case tcp = "TCP"
    case udp = "UDP"
}

public enum PortState: Hashable, Sendable {
    case listen
    case other(String)

    public init(lsofValue: String) {
        self = lsofValue.uppercased() == "LISTEN" ? .listen : .other(lsofValue)
    }

    public var label: String {
        switch self {
        case .listen: return "LISTEN"
        case .other(let value): return value
        }
    }
}

/// One listening socket and the process that owns it. Pure data: no UI state.
public struct PortInfo: Identifiable, Hashable, Sendable {
    public let id: String
    public let port: Int
    public let protocolType: PortProtocol
    /// Bound address. `*` means wildcard; IPv6 addresses have no brackets.
    public let address: String
    public let processName: String
    public let pid: Int
    public let user: String?
    public let state: PortState?
    /// Process start time (seconds since epoch). Used with the PID to detect PID reuse.
    public let startTime: TimeInterval?

    public init(
        port: Int,
        protocolType: PortProtocol,
        address: String,
        processName: String,
        pid: Int,
        user: String? = nil,
        state: PortState? = nil,
        startTime: TimeInterval? = nil
    ) {
        self.id = "\(protocolType.rawValue)-\(pid)-\(address)-\(port)"
        self.port = port
        self.protocolType = protocolType
        self.address = address
        self.processName = processName
        self.pid = pid
        self.user = user
        self.state = state
        self.startTime = startTime
    }

    /// e.g. `127.0.0.1:3000`, `[::1]:3000`, `*:3000`.
    public var endpoint: String {
        address.contains(":") ? "[\(address)]:\(port)" : "\(address):\(port)"
    }

    public func withStartTime(_ startTime: TimeInterval?) -> PortInfo {
        PortInfo(
            port: port, protocolType: protocolType, address: address,
            processName: processName, pid: pid, user: user, state: state,
            startTime: startTime
        )
    }
}
