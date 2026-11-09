import Foundation
import MacPeekCore

/// One proxy macOS is configured to use for a protocol.
public struct ProxyEndpoint: Equatable, Codable, Sendable {
    public let host: String
    public let port: Int?

    public init(host: String, port: Int?) {
        self.host = host
        self.port = port
    }

    public var label: String { port.map { "\(host):\($0)" } ?? host }
}

/// The system proxy settings (`scutil --proxy`). Apps that use the system networking stack follow them; most
/// command-line tools do not, and use `HTTP_PROXY`/`HTTPS_PROXY` instead, which is a common source of confusion.
public struct ProxySettings: Equatable, Codable, Sendable {
    public let http: ProxyEndpoint?
    public let https: ProxyEndpoint?
    public let socks: ProxyEndpoint?
    /// A proxy auto-configuration (PAC) file URL.
    public let autoConfigURL: String?
    /// Web Proxy Auto-Discovery (WPAD).
    public let autoDiscovery: Bool
    /// Hosts and domains that bypass the proxy.
    public let exceptions: [String]
    public let excludesSimpleHostnames: Bool

    public init(http: ProxyEndpoint?, https: ProxyEndpoint?, socks: ProxyEndpoint?, autoConfigURL: String?, autoDiscovery: Bool,
                exceptions: [String], excludesSimpleHostnames: Bool) {
        self.http = http
        self.https = https
        self.socks = socks
        self.autoConfigURL = autoConfigURL
        self.autoDiscovery = autoDiscovery
        self.exceptions = exceptions
        self.excludesSimpleHostnames = excludesSimpleHostnames
    }

    public var isAnyEnabled: Bool { http != nil || https != nil || socks != nil || autoConfigURL != nil || autoDiscovery }

    /// "HTTP proxy.corp:8080, HTTPS proxy.corp:8080, PAC http://wpad/wpad.dat" or "None".
    public var summary: String {
        var parts: [String] = []
        if let http { parts.append("HTTP \(http.label)") }
        if let https { parts.append("HTTPS \(https.label)") }
        if let socks { parts.append("SOCKS \(socks.label)") }
        if let autoConfigURL { parts.append("PAC \(autoConfigURL)") }
        if autoDiscovery { parts.append("auto-discovery (WPAD)") }
        return parts.isEmpty ? "None" : parts.joined(separator: ", ")
    }
}

/// A VPN or other network connection service macOS knows (`scutil --nc list`), including VPN apps that use Apple's
/// Network Extension (WireGuard, Tailscale, many corporate VPNs).
public struct VPNService: Identifiable, Equatable, Codable, Sendable {
    public var id: String { name + "|" + type }
    public let name: String
    /// macOS's word: "Connected", "Disconnected", "Connecting"…
    public let status: String
    /// "VPN:com.wireguard.macos", "PPP:L2TP", "IPSec".
    public let type: String
    public let enabled: Bool

    public init(name: String, status: String, type: String, enabled: Bool) {
        self.name = name
        self.status = status
        self.type = type
        self.enabled = enabled
    }

    public var isConnected: Bool { status.lowercased() == "connected" }
    public var isConnecting: Bool { ["connecting", "reasserting", "disconnecting"].contains(status.lowercased()) }
}

/// What `tailscale status --json` says about this Mac's tailnet.
public struct TailscaleStatus: Equatable, Codable, Sendable {
    /// "Running", "Stopped", "NeedsLogin", "Starting"…
    public let backendState: String
    public let selfName: String?
    public let selfAddresses: [String]
    public let tailnet: String?
    public let magicDNSSuffix: String?
    public let peersOnline: Int
    public let peersTotal: Int
    /// The exit node all internet traffic goes through, when one is in use.
    public let exitNode: String?
    /// Tailscale's own health warnings.
    public let health: [String]

    public init(backendState: String, selfName: String?, selfAddresses: [String], tailnet: String?, magicDNSSuffix: String?,
                peersOnline: Int, peersTotal: Int, exitNode: String?, health: [String]) {
        self.backendState = backendState
        self.selfName = selfName
        self.selfAddresses = selfAddresses
        self.tailnet = tailnet
        self.magicDNSSuffix = magicDNSSuffix
        self.peersOnline = peersOnline
        self.peersTotal = peersTotal
        self.exitNode = exitNode
        self.health = health
    }

    public var isRunning: Bool { backendState == "Running" }
}

/// Network facts beyond the connection itself, the kind that explain "it works in the browser but not in Terminal".
public struct NetExtras: Equatable, Codable, Sendable {
    public let proxy: ProxySettings?
    public let vpns: [VPNService]
    public let tailscale: TailscaleStatus?
    /// Why Tailscale's state is missing when its tool is installed.
    public let tailscaleNote: String?
    /// Remembered Wi-Fi networks, most preferred first. Nil when there is no Wi-Fi interface or macOS did not list them.
    public let preferredWiFi: [String]?

    public init(proxy: ProxySettings?, vpns: [VPNService], tailscale: TailscaleStatus?, tailscaleNote: String?, preferredWiFi: [String]?) {
        self.proxy = proxy
        self.vpns = vpns
        self.tailscale = tailscale
        self.tailscaleNote = tailscaleNote
        self.preferredWiFi = preferredWiFi
    }

    public var connectedVPNs: [VPNService] { vpns.filter(\.isConnected) }

    /// Plain-language consequences, each one a likely reason something "works here but not there".
    public var findings: [String] {
        var result: [String] = []
        if let proxy, proxy.isAnyEnabled {
            result.append("A system proxy is set (\(proxy.summary)). Apps follow it, but most command-line tools ignore it unless HTTP_PROXY or HTTPS_PROXY is set, so they may behave differently.")
        }
        for vpn in connectedVPNs {
            result.append("\(vpn.name) is connected: some or all traffic and DNS may go through it.")
        }
        if let tailscale, tailscale.isRunning, let exit = tailscale.exitNode {
            result.append("Tailscale sends all internet traffic through the exit node \(exit).")
        }
        if let tailscale, !tailscale.isRunning {
            result.append("Tailscale is \(tailscale.backendState): tailnet names and 100.x addresses will not resolve or connect.")
        }
        if let health = tailscale?.health, !health.isEmpty {
            result.append(contentsOf: health.map { "Tailscale: \($0)" })
        }
        return result
    }
}

/// `scutil --proxy`: a nested dictionary printed as text. Only the top level (and its exceptions list) is read.
public enum ProxyParser {
    private static let keyValue = NSRegularExpression.compile(#"^\s*([A-Za-z_]+)\s*:\s*(.*?)\s*$"#)
    private static let arrayItem = NSRegularExpression.compile(#"^\s*\d+\s*:\s*(.+?)\s*$"#)

    public static func parse(_ text: String) -> ProxySettings? {
        guard text.contains("<dictionary>") else { return nil }
        var values: [String: String] = [:]
        var exceptions: [String] = []
        var depth = 0
        var inExceptions = false
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "}" {
                depth -= 1
                if depth == 1 { inExceptions = false }
                continue
            }
            if depth == 1, let g = keyValue.groups(in: line), let key = g[1], let value = g[2] {
                if value.hasSuffix("{") {
                    depth += 1
                    inExceptions = key == "ExceptionsList"
                } else {
                    values[key] = value
                }
                continue
            }
            if depth == 2, inExceptions, let g = arrayItem.groups(in: line), let item = g[1] {
                exceptions.append(item)
                continue
            }
            if trimmed.hasSuffix("{") { depth += 1 }
        }
        func enabled(_ key: String) -> Bool { values[key] == "1" }
        func endpoint(_ prefix: String) -> ProxyEndpoint? {
            guard enabled("\(prefix)Enable"), let host = values["\(prefix)Proxy"], !host.isEmpty else { return nil }
            return ProxyEndpoint(host: host, port: values["\(prefix)Port"].flatMap(Int.init))
        }
        return ProxySettings(http: endpoint("HTTP"), https: endpoint("HTTPS"), socks: endpoint("SOCKS"),
                             autoConfigURL: enabled("ProxyAutoConfigEnable") ? values["ProxyAutoConfigURLString"] : nil,
                             autoDiscovery: enabled("ProxyAutoDiscoveryEnable"), exceptions: exceptions,
                             excludesSimpleHostnames: enabled("ExcludeSimpleHostnames"))
    }
}

/// `scutil --nc list`: `* (Connected)   <UUID> VPN (com.wireguard.macos) "Home"   [VPN:com.wireguard.macos]`.
public enum VPNListParser {
    private static let line = NSRegularExpression.compile(#"^\s*(\*)?\s*\(([^)]+)\)\s+[0-9A-Fa-f-]{36}\s+.*?"(.+)"\s*\[([^\]]+)\]\s*$"#)

    public static func parse(_ text: String) -> [VPNService] {
        text.split(whereSeparator: \.isNewline).compactMap { raw in
            guard let g = line.groups(in: String(raw)), let status = g[2], let name = g[3], let type = g[4] else { return nil }
            return VPNService(name: name, status: status, type: type, enabled: g[1] != nil)
        }
    }
}

/// `tailscale status --json`.
public enum TailscaleParser {
    public static func parse(_ text: String) -> TailscaleStatus? {
        guard let root = LooseJSON.parse(text) as? LooseJSON.Object, let state = LooseJSON.text(root, "BackendState") else { return nil }
        let me = LooseJSON.object(root, "Self") ?? [:]
        let peers = (root["Peer"] as? [String: Any] ?? [:]).values.compactMap { $0 as? LooseJSON.Object }
        let exit = peers.first { LooseJSON.bool($0, "ExitNode") == true }
        let tailnet = LooseJSON.object(root, "CurrentTailnet")
        return TailscaleStatus(
            backendState: state, selfName: LooseJSON.text(me, "HostName") ?? trimmedDNS(LooseJSON.text(me, "DNSName")),
            selfAddresses: LooseJSON.strings(me, "TailscaleIPs"),
            tailnet: tailnet.flatMap { LooseJSON.text($0, "Name") },
            magicDNSSuffix: tailnet.flatMap { LooseJSON.text($0, "MagicDNSSuffix") } ?? LooseJSON.text(root, "MagicDNSSuffix"),
            peersOnline: peers.filter { LooseJSON.bool($0, "Online") == true }.count, peersTotal: peers.count,
            exitNode: exit.flatMap { LooseJSON.text($0, "HostName") ?? trimmedDNS(LooseJSON.text($0, "DNSName")) },
            health: LooseJSON.strings(root, "Health"))
    }

    private static func trimmedDNS(_ name: String?) -> String? {
        guard let name else { return nil }
        return name.hasSuffix(".") ? String(name.dropLast()) : name
    }
}

/// `networksetup -listpreferredwirelessnetworks en0`: a heading, then one indented name per line.
public enum PreferredWiFiParser {
    public static func parse(_ text: String) -> [String]? {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard let header = lines.first, header.lowercased().hasPrefix("preferred networks on") else { return nil }
        return lines.dropFirst().map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

public protocol NetworkExtrasReading: Sendable {
    /// Proxy, VPN and Tailscale state, and remembered Wi-Fi networks for `wifiInterface` when it is a Wi-Fi interface.
    func extras(wifiInterface: String?) async throws -> NetExtras
}

extension SystemNetworkReader: NetworkExtrasReading {
    static let tailscaleLocator = ExecutableLocator.standard("tailscale", extra: ["/Applications/Tailscale.app/Contents/MacOS/Tailscale"])

    public func extras(wifiInterface: String?) async throws -> NetExtras {
        try await extras(wifiInterface: wifiInterface, tailscale: Self.tailscaleLocator)
    }

    func extras(wifiInterface: String?, tailscale locator: ExecutableLocator) async throws -> NetExtras {
        let proxy = try await attemptExtra(Self.scutil, ["--proxy"]).flatMap { $0.status == 0 ? ProxyParser.parse($0.stdout) : nil }
        let vpns = try await attemptExtra(Self.scutil, ["--nc", "list"]).map { $0.status == 0 ? VPNListParser.parse($0.stdout) : [] } ?? []
        var status: TailscaleStatus?
        var note: String?
        if let path = locator.locate() {
            if let output = try await attemptExtra(path, ["status", "--json"]) {
                status = TailscaleParser.parse(output.stdout)
                if status == nil {
                    let detail = output.stderr.split(whereSeparator: \.isNewline).first.map(String.init)
                    note = detail ?? "Tailscale did not describe its state."
                }
            } else {
                note = "Tailscale did not answer."
            }
        }
        var preferred: [String]?
        if let wifiInterface, NetInterfaceName.isValid(wifiInterface),
           let output = try await attemptExtra(Self.networksetup, ["-listpreferredwirelessnetworks", wifiInterface]), output.status == 0 {
            preferred = PreferredWiFiParser.parse(output.stdout)
        }
        return NetExtras(proxy: proxy, vpns: vpns, tailscale: status, tailscaleNote: note, preferredWiFi: preferred)
    }

    private func attemptExtra(_ executable: String, _ arguments: [String]) async throws -> CommandOutput? {
        do { return try await extrasRunner.run(executable, arguments) }
        catch is CancellationError { throw CancellationError() }
        catch CommandError.cancelled { throw CommandError.cancelled }
        catch { return nil }
    }
}

/// BSD interface names (`en0`, `utun3`, `bridge100`): the only values passed to networksetup as an interface.
public enum NetInterfaceName {
    private static let pattern = NSRegularExpression.compile(#"^[a-z]{1,12}[0-9]{1,4}$"#)
    public static func isValid(_ name: String) -> Bool { pattern.groups(in: name) != nil }
}
