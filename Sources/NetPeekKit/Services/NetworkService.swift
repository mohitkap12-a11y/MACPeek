import Foundation
import MacPeekCore
import DNSPeekKit

public enum NetError: Error, Equatable, LocalizedError {
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let detail): return detail
        }
    }
}

public protocol NetworkReading: Sendable {
    /// Cheap and read-only: the active interface, addresses, gateway and DNS servers.
    func snapshot() async throws -> NetSnapshot
    /// Slower (`system_profiler`): Wi-Fi details for `interface`.
    func wifi(interface: String) async throws -> WiFiInfo?
    /// Pings the gateway and the DNS servers. Only runs when the user asks.
    func runChecks(for snapshot: NetSnapshot) async throws -> NetworkChecks
}

public struct SystemNetworkReader: NetworkReading {
    static let route = "/sbin/route"
    static let scutil = "/usr/sbin/scutil"
    static let networksetup = "/usr/sbin/networksetup"
    static let systemProfiler = "/usr/sbin/system_profiler"
    static let ping = "/sbin/ping"
    private let runner: CommandRunning
    private let dns: DNSReading

    public init(runner: CommandRunning = ShellCommand(timeout: 20), dns: DNSReading = SystemDNSReader()) {
        self.runner = runner
        self.dns = dns
    }

    /// Runs a command; a failure to run it is nil, but cancellation always propagates.
    private func attempt(_ executable: String, _ arguments: [String]) async throws -> CommandOutput? {
        do { return try await runner.run(executable, arguments) }
        catch is CancellationError { throw CancellationError() }
        catch CommandError.cancelled { throw CommandError.cancelled }
        catch { return nil }
    }

    public func snapshot() async throws -> NetSnapshot {
        // `route` exits 1 when there is no default route: that is an answer ("not connected"), not a failure.
        let route = try await attempt(Self.route, ["-n", "get", "default"])
        let nwi = try await attempt(Self.scutil, ["--nwi"])
        // `scutil --nwi` succeeds even when offline, and `route` succeeds when there is a default route: if neither did,
        // the tools themselves are unavailable, which is different from "not connected".
        guard nwi?.status == 0 || route?.status == 0 else { throw NetError.unavailable("macOS network information could not be read.") }
        let ports = try await attempt(Self.networksetup, ["-listallhardwareports"])

        var dnsServers: [String] = []
        do { dnsServers = try await dns.configuration().activeServers }
        catch is CancellationError { throw CancellationError() }
        catch CommandError.cancelled { throw CommandError.cancelled }
        catch { dnsServers = [] }

        let defaultRoute = (route?.status == 0) ? RouteParser.parse(route?.stdout ?? "") : nil
        let entries = (nwi?.status == 0) ? NWIParser.parse(nwi?.stdout ?? "") : []
        let names = (ports?.status == 0) ? HardwarePortParser.parse(ports?.stdout ?? "") : [:]

        var order: [String] = []
        for entry in entries where !order.contains(entry.name) { order.append(entry.name) }
        let interfaces: [NetInterface] = order.map { name in
            let mine = entries.filter { $0.name == name }
            return NetInterface(
                name: name, hardwarePort: names[name],
                ipv4Addresses: mine.filter { $0.family == .v4 }.compactMap(\.address),
                ipv6Addresses: mine.filter { $0.family == .v6 }.compactMap(\.address),
                reachability: mine.compactMap(\.reachability).first)
        }

        let primaryName = defaultRoute?.interface
        var primary = primaryName.flatMap { name in interfaces.first { $0.name == name } }
        if primary == nil, let primaryName {
            primary = NetInterface(name: primaryName, hardwarePort: names[primaryName], ipv4Addresses: [], ipv6Addresses: [], reachability: nil)
        }
        if primary == nil { primary = interfaces.first { !$0.ipv4Addresses.isEmpty } }

        return NetSnapshot(primary: primary, otherInterfaces: interfaces.filter { $0.name != primary?.name },
                           gateway: defaultRoute?.gateway, dnsServers: dnsServers, hasDefaultRoute: defaultRoute != nil)
    }

    public func wifi(interface: String) async throws -> WiFiInfo? {
        guard let output = try await attempt(Self.systemProfiler, ["SPAirPortDataType", "-json"]), output.status == 0 else { return nil }
        return WiFiParser.parse(output.stdout, interface: interface)
    }

    public func runChecks(for snapshot: NetSnapshot) async throws -> NetworkChecks {
        var targets: [String] = []
        if let gateway = snapshot.gateway { targets.append(gateway) }
        let servers = Array(snapshot.dnsServers.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.prefix(3))
        targets.append(contentsOf: servers)

        // Pings run side by side so an unresponsive target costs one timeout, not one per target.
        let outcomes = try await withThrowingTaskGroup(of: (Int, PingOutcome).self) { group -> [PingOutcome?] in
            for (index, host) in targets.enumerated() {
                group.addTask { (index, try await self.ping(host)) }
            }
            var results = [PingOutcome?](repeating: nil, count: targets.count)
            for try await (index, outcome) in group { results[index] = outcome }
            return results
        }
        let hasGateway = snapshot.gateway != nil
        return NetworkChecks(gateway: hasGateway ? outcomes.first ?? nil : nil,
                             dnsServers: outcomes.dropFirst(hasGateway ? 1 : 0).compactMap { $0 })
    }

    func ping(_ host: String) async throws -> PingOutcome {
        // Only IPv4 literals are pinged, and only after validation: nothing here can become a ping option.
        guard NetworkInput.isIPv4(host) else {
            return .skipped(host: host, reason: NetworkInput.isIPv6(host) ? "IPv6 addresses are not checked." : "Not an IPv4 address.")
        }
        guard let output = try await attempt(Self.ping, ["-c", "3", "-t", "5", host]) else {
            return .failed(host: host, reason: "ping could not run.")
        }
        if let result = PingParser.parse(output.stdout, host: host) { return .result(result) }
        let detail = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return .failed(host: host, reason: detail.isEmpty ? "ping printed nothing MacPeek understands." : detail)
    }
}
