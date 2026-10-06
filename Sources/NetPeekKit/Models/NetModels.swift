import Foundation

public struct NetInterface: Identifiable, Equatable, Sendable {
    public var id: String { name }
    /// BSD name, e.g. "en1".
    public let name: String
    /// networksetup's name for it: "Wi-Fi", "Ethernet", "Thunderbolt Bridge"…
    public let hardwarePort: String?
    public let ipv4Addresses: [String]
    public let ipv6Addresses: [String]
    /// macOS's own words for the interface's reachability: "Reachable", "Not Reachable"…
    public let reachability: String?

    public init(name: String, hardwarePort: String?, ipv4Addresses: [String], ipv6Addresses: [String], reachability: String?) {
        self.name = name
        self.hardwarePort = hardwarePort
        self.ipv4Addresses = ipv4Addresses
        self.ipv6Addresses = ipv6Addresses
        self.reachability = reachability
    }

    public var isWiFi: Bool { hardwarePort?.lowercased().contains("wi-fi") == true }
    public var displayName: String { hardwarePort ?? name }
    public var isReachable: Bool? { reachability.map { !$0.lowercased().contains("not") } }
}

public struct NetSnapshot: Equatable, Sendable {
    /// The interface the default route uses (or, with no default route, the first one with an IPv4 address).
    public let primary: NetInterface?
    public let otherInterfaces: [NetInterface]
    /// The default IPv4 gateway, when there is a default route.
    public let gateway: String?
    public let dnsServers: [String]
    public let hasDefaultRoute: Bool

    public init(primary: NetInterface?, otherInterfaces: [NetInterface], gateway: String?, dnsServers: [String], hasDefaultRoute: Bool) {
        self.primary = primary
        self.otherInterfaces = otherInterfaces
        self.gateway = gateway
        self.dnsServers = dnsServers
        self.hasDefaultRoute = hasDefaultRoute
    }

    /// Plain text for a support thread.
    public var copyText: String {
        guard let primary else { return "No active network connection." }
        var lines = ["Interface: \(primary.displayName) (\(primary.name))"]
        if !primary.ipv4Addresses.isEmpty { lines.append("IPv4: " + primary.ipv4Addresses.joined(separator: ", ")) }
        if !primary.ipv6Addresses.isEmpty { lines.append("IPv6: " + primary.ipv6Addresses.joined(separator: ", ")) }
        if let gateway { lines.append("Gateway: \(gateway)") }
        if !dnsServers.isEmpty { lines.append("DNS: " + dnsServers.joined(separator: ", ")) }
        return lines.joined(separator: "\n")
    }
}

public struct WiFiInfo: Equatable, Sendable {
    /// Nil when macOS hides the name (it does unless the app has Location access, which MacPeek does not ask for).
    public let networkName: String?
    public let channel: String?
    public let phyMode: String?
    /// The link rate in Mb/s that the radio negotiated (not an internet speed).
    public let transmitRateMbps: Int?
    public let security: String?
    public let signalDBm: Int?
    public let noiseDBm: Int?
    public let countryCode: String?
    public let isConnected: Bool

    public init(networkName: String?, channel: String?, phyMode: String?, transmitRateMbps: Int?, security: String?,
                signalDBm: Int?, noiseDBm: Int?, countryCode: String?, isConnected: Bool) {
        self.networkName = networkName
        self.channel = channel
        self.phyMode = phyMode
        self.transmitRateMbps = transmitRateMbps
        self.security = security
        self.signalDBm = signalDBm
        self.noiseDBm = noiseDBm
        self.countryCode = countryCode
        self.isConnected = isConnected
    }

    /// Signal minus noise, in dB.
    public var signalToNoise: Int? {
        guard let signalDBm, let noiseDBm else { return nil }
        return signalDBm - noiseDBm
    }

    /// A common rule of thumb for the signal strength, not something macOS reports.
    public var signalQuality: String? {
        guard let signalDBm else { return nil }
        switch signalDBm {
        case (-50)...: return "Excellent"
        case (-60)...: return "Good"
        case (-70)...: return "Fair"
        default: return "Weak"
        }
    }
}

public struct PingResult: Identifiable, Equatable, Sendable {
    public var id: String { host }
    public let host: String
    public let transmitted: Int
    public let received: Int
    public let lossPercent: Double
    public let minMilliseconds: Double?
    public let averageMilliseconds: Double?
    public let maxMilliseconds: Double?

    public init(host: String, transmitted: Int, received: Int, lossPercent: Double,
                minMilliseconds: Double?, averageMilliseconds: Double?, maxMilliseconds: Double?) {
        self.host = host
        self.transmitted = transmitted
        self.received = received
        self.lossPercent = lossPercent
        self.minMilliseconds = minMilliseconds
        self.averageMilliseconds = averageMilliseconds
        self.maxMilliseconds = maxMilliseconds
    }

    public var gotReplies: Bool { received > 0 }
}

/// What a ping check could say about one target.
public enum PingOutcome: Equatable, Sendable {
    case result(PingResult)
    /// The target was not pinged, with the reason (for example an IPv6 server: only IPv4 is checked).
    case skipped(host: String, reason: String)
    case failed(host: String, reason: String)

    public var host: String {
        switch self {
        case .result(let r): return r.host
        case .skipped(let h, _), .failed(let h, _): return h
        }
    }
}

public struct NetworkChecks: Equatable, Sendable {
    public let gateway: PingOutcome?
    public let dnsServers: [PingOutcome]

    public init(gateway: PingOutcome?, dnsServers: [PingOutcome]) {
        self.gateway = gateway
        self.dnsServers = dnsServers
    }
}
