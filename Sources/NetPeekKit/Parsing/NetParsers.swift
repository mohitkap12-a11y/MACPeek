import Foundation

/// `route -n get default` (verified against a real Mac):
///
///        route to: default
///     destination: default
///         gateway: 192.168.68.1
///       interface: en1
public enum RouteParser {
    public struct DefaultRoute: Equatable, Sendable {
        public let gateway: String?
        public let interface: String?
    }

    private static let line = NSRegularExpression.compile(#"^\s*(gateway|interface):\s*(\S+)\s*$"#)

    public static func parse(_ text: String) -> DefaultRoute? {
        var gateway: String?
        var interface: String?
        for l in text.split(separator: "\n") {
            guard let g = line.groups(in: String(l)), let key = g[1], let value = g[2] else { continue }
            if key == "gateway" { gateway = value } else { interface = value }
        }
        return gateway == nil && interface == nil ? nil : DefaultRoute(gateway: gateway, interface: interface)
    }
}

/// `scutil --nwi` (verified against a real Mac):
///
///     IPv4 network interface information
///          en1 : flags      : 0x7 (IPv4,IPv6,DNS)
///                address    : 192.168.68.106
///                reach      : 0x00000002 (Reachable)
public enum NWIParser {
    public struct Entry: Equatable, Sendable {
        public enum Family: Sendable { case v4, v6 }
        public let name: String
        public let family: Family
        public var address: String?
        public var reachability: String?
    }

    private static let interfaceLine = NSRegularExpression.compile(#"^\s*([A-Za-z0-9]+)\s*:\s*flags\s*:"#)
    private static let addressLine = NSRegularExpression.compile(#"^\s*address\s*:\s*(\S+)"#)
    private static let reachLine = NSRegularExpression.compile(#"^\s*reach\s*:\s*0x[0-9A-Fa-f]+\s*\(([^)]*)\)"#)

    public static func parse(_ text: String) -> [Entry] {
        var entries: [Entry] = []
        var family = Entry.Family.v4
        for l in text.split(separator: "\n").map(String.init) {
            if l.hasPrefix("IPv4 network interface") { family = .v4; continue }
            if l.hasPrefix("IPv6 network interface") { family = .v6; continue }
            if let g = interfaceLine.groups(in: l), let name = g[1] {
                entries.append(Entry(name: name, family: family, address: nil, reachability: nil))
            } else if !entries.isEmpty, let g = addressLine.groups(in: l) {
                entries[entries.count - 1].address = g[1]
            } else if !entries.isEmpty, let g = reachLine.groups(in: l) {
                // The trailing "REACH : flags …" summary has no leading interface and no "0x… (" form, so it is skipped.
                entries[entries.count - 1].reachability = g[1]
            }
        }
        return entries
    }
}

/// `networksetup -listallhardwareports` (verified against a real Mac): blocks of `Hardware Port:` / `Device:`.
public enum HardwarePortParser {
    public static func parse(_ text: String) -> [String: String] {
        var ports: [String: String] = [:]
        var port: String?
        for l in text.split(separator: "\n") {
            if l.hasPrefix("Hardware Port:") {
                port = l.dropFirst("Hardware Port:".count).trimmingCharacters(in: .whitespaces)
            } else if l.hasPrefix("Device:"), let port {
                let device = l.dropFirst("Device:".count).trimmingCharacters(in: .whitespaces)
                if !device.isEmpty { ports[device] = port }
            }
        }
        return ports
    }
}

/// `ping -c 3 -t 5 <ip>` (verified against a real Mac).
public enum PingParser {
    private static let packets = NSRegularExpression.compile(#"(\d+) packets transmitted, (\d+) packets received, ([0-9.]+)% packet loss"#)
    private static let roundTrip = NSRegularExpression.compile(#"round-trip min/avg/max/(?:stddev|std-dev) = ([0-9.]+)/([0-9.]+)/([0-9.]+)"#)

    public static func parse(_ text: String, host: String) -> PingResult? {
        guard let p = packets.groups(in: text), let sent = p[1].flatMap({ Int($0) }),
              let received = p[2].flatMap({ Int($0) }), let loss = p[3].flatMap({ Double($0) }) else { return nil }
        let r = roundTrip.groups(in: text)
        return PingResult(host: host, transmitted: sent, received: received, lossPercent: loss,
                          minMilliseconds: r?[1].flatMap { Double($0) },
                          averageMilliseconds: r?[2].flatMap { Double($0) },
                          maxMilliseconds: r?[3].flatMap { Double($0) })
    }
}

/// `system_profiler SPAirPortDataType -json` (verified against a real Mac).
///
/// macOS replaces the network name with `<redacted>` for apps without Location access; that is surfaced as a nil
/// name rather than shown as if it were the name.
public enum WiFiParser {
    private static let signal = NSRegularExpression.compile(#"(-?\d+)\s*dBm\s*/\s*(-?\d+)\s*dBm"#)

    public static func parse(_ text: String, interface: String) -> WiFiInfo? {
        guard let start = text.firstIndex(of: "{"),
              let data = String(text[start...]).data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cards = root["SPAirPortDataType"] as? [[String: Any]] else { return nil }
        for card in cards {
            let interfaces = card["spairport_airport_interfaces"] as? [[String: Any]] ?? []
            guard let wifi = interfaces.first(where: { ($0["_name"] as? String) == interface }) else { continue }
            let status = (wifi["spairport_status_information"] as? String) ?? ""
            let connected = status.hasSuffix("connected") && !status.hasSuffix("disconnected")
            guard let network = wifi["spairport_current_network_information"] as? [String: Any], connected else {
                return WiFiInfo(networkName: nil, channel: nil, phyMode: nil, transmitRateMbps: nil, security: nil,
                                signalDBm: nil, noiseDBm: nil, countryCode: nil, isConnected: false)
            }
            let name = (network["_name"] as? String).flatMap { $0.isEmpty || $0 == "<redacted>" ? nil : $0 }
            let sn = (network["spairport_signal_noise"] as? String).flatMap { signal.groups(in: $0) }
            return WiFiInfo(
                networkName: name,
                channel: network["spairport_network_channel"] as? String,
                phyMode: network["spairport_network_phymode"] as? String,
                transmitRateMbps: network["spairport_network_rate"] as? Int,
                security: (network["spairport_security_mode"] as? String).map(humanizeSecurity),
                signalDBm: sn?[1].flatMap { Int($0) },
                noiseDBm: sn?[2].flatMap { Int($0) },
                countryCode: network["spairport_network_country_code"] as? String,
                isConnected: true)
        }
        return nil
    }

    /// "spairport_security_mode_wpa2_personal" → "WPA2 Personal".
    static func humanizeSecurity(_ raw: String) -> String {
        let trimmed = raw.replacingOccurrences(of: "spairport_security_mode_", with: "")
        let words = trimmed.split(separator: "_").map { word -> String in
            let w = String(word)
            return w.lowercased().hasPrefix("wpa") || w.lowercased() == "wep" ? w.uppercased() : w.prefix(1).uppercased() + w.dropFirst()
        }
        return words.joined(separator: " ")
    }
}
