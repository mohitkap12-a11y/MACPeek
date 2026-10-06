import XCTest
@testable import NetPeekKit
import DNSPeekKit
import MacPeekCore

func fixture(_ name: String) throws -> String {
    guard let url = Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures") else {
        throw NSError(domain: "fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing \(name)"])
    }
    return try String(contentsOf: url, encoding: .utf8)
}

final class ParserTests: XCTestCase {
    func testRouteRealOutput() throws {
        let route = try XCTUnwrap(RouteParser.parse(try fixture("route_default")))
        XCTAssertEqual(route.gateway, "192.168.68.1")
        XCTAssertEqual(route.interface, "en1")
        XCTAssertNil(RouteParser.parse("route: writing to routing socket: not in table\n"))
        XCTAssertNil(RouteParser.parse(""))
    }

    func testNWIRealOutput() throws {
        let entries = NWIParser.parse(try fixture("scutil_nwi"))
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].name, "en1")
        XCTAssertEqual(entries[0].family, .v4)
        XCTAssertEqual(entries[0].address, "192.168.68.106")
        XCTAssertEqual(entries[0].reachability, "Reachable")
        XCTAssertEqual(entries[1].family, .v6)
        XCTAssertEqual(entries[1].address, "fd00:1234:5678:9abc:1111:2222:3333:4444")
        XCTAssertTrue(NWIParser.parse("Network information\n\nNo IPv4 states found\n").isEmpty)
    }

    func testHardwarePortsRealOutput() throws {
        let ports = HardwarePortParser.parse(try fixture("hardware_ports"))
        XCTAssertEqual(ports["en1"], "Wi-Fi")
        XCTAssertEqual(ports["en0"], "Ethernet")
        XCTAssertEqual(ports["bridge0"], "Thunderbolt Bridge")
        XCTAssertEqual(ports["en4"], "Ethernet Adapter (en4)")
        XCTAssertEqual(ports.count, 7)
    }

    func testPingRealOutput() throws {
        let ping = try XCTUnwrap(PingParser.parse(try fixture("ping_3"), host: "1.1.1.1"))
        XCTAssertEqual(ping.transmitted, 3)
        XCTAssertEqual(ping.received, 3)
        XCTAssertEqual(ping.lossPercent, 0)
        XCTAssertEqual(try XCTUnwrap(ping.minMilliseconds), 15.697, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(ping.averageMilliseconds), 19.740, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(ping.maxMilliseconds), 25.593, accuracy: 0.0001)
        XCTAssertTrue(ping.gotReplies)
    }

    func testPingWithNoRepliesHasNoLatency() throws {
        let text = "PING 10.0.0.9 (10.0.0.9): 56 data bytes\nRequest timeout for icmp_seq 0\n\n--- 10.0.0.9 ping statistics ---\n3 packets transmitted, 0 packets received, 100.0% packet loss\n"
        let ping = try XCTUnwrap(PingParser.parse(text, host: "10.0.0.9"))
        XCTAssertEqual(ping.received, 0)
        XCTAssertEqual(ping.lossPercent, 100)
        XCTAssertNil(ping.averageMilliseconds)
        XCTAssertFalse(ping.gotReplies)
        XCTAssertNil(PingParser.parse("ping: cannot resolve", host: "x"))
    }

    func testWiFiRealOutputWithTheNameHiddenByMacOS() throws {
        let wifi = try XCTUnwrap(WiFiParser.parse(try fixture("wifi_profiler"), interface: "en1"))
        XCTAssertTrue(wifi.isConnected)
        XCTAssertNil(wifi.networkName, "macOS printed <redacted>: that is not a name")
        XCTAssertEqual(wifi.channel, "36 (5GHz, 80MHz)")
        XCTAssertEqual(wifi.phyMode, "802.11ac")
        XCTAssertEqual(wifi.transmitRateMbps, 866)
        XCTAssertEqual(wifi.security, "WPA2 Personal")
        XCTAssertEqual(wifi.signalDBm, -35)
        XCTAssertEqual(wifi.noiseDBm, -89)
        XCTAssertEqual(wifi.signalToNoise, 54)
        XCTAssertEqual(wifi.signalQuality, "Excellent")
        XCTAssertEqual(wifi.countryCode, "IN")
    }

    func testWiFiForAnotherInterfaceOrGarbageIsNil() throws {
        XCTAssertNil(WiFiParser.parse(try fixture("wifi_profiler"), interface: "en9"))
        XCTAssertNil(WiFiParser.parse("not json", interface: "en1"))
    }

    func testSignalQualityBands() {
        func quality(_ dbm: Int) -> String? {
            WiFiInfo(networkName: nil, channel: nil, phyMode: nil, transmitRateMbps: nil, security: nil, signalDBm: dbm,
                     noiseDBm: nil, countryCode: nil, isConnected: true).signalQuality
        }
        XCTAssertEqual(quality(-50), "Excellent")
        XCTAssertEqual(quality(-51), "Good")
        XCTAssertEqual(quality(-60), "Good")
        XCTAssertEqual(quality(-65), "Fair")
        XCTAssertEqual(quality(-70), "Fair")
        XCTAssertEqual(quality(-80), "Weak")
    }
}

private final class Router: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [[String]] = []
    let responses: [String: CommandOutput]
    init(_ responses: [String: CommandOutput]) { self.responses = responses }
    var calls: [[String]] { lock.lock(); defer { lock.unlock() }; return _calls }
    private func record(_ line: [String]) { lock.lock(); defer { lock.unlock() }; _calls.append(line) }
    func run(_ executable: String, _ arguments: [String]) async throws -> CommandOutput {
        record([executable] + arguments)
        return responses[([executable] + arguments).joined(separator: " ")]
            ?? CommandOutput(stdout: "", stderr: "unscripted: \(executable)", status: 1)
    }
}

private struct FakeDNS: DNSReading {
    let servers: [String]
    func configuration() async throws -> DNSConfiguration {
        let r = DNSResolver(id: "default-1", number: 1, nameservers: servers, domain: nil, searchDomains: [], interface: "en1", options: nil,
                            timeoutSeconds: nil, flags: [], reachability: "Reachable", order: nil, isScoped: false)
        return DNSConfiguration(resolvers: [r], scopedResolvers: [])
    }
    func lookup(name: String) async throws -> SystemLookup { SystemLookup(name: name, addresses: [], elapsedMilliseconds: 0) }
    func probe(server: String, name: String) async throws -> ServerProbe { ServerProbe(server: server, outcome: .timedOut) }
}

final class ServiceTests: XCTestCase {
    private func ok(_ text: String, status: Int32 = 0) -> CommandOutput { CommandOutput(stdout: text, stderr: "", status: status) }

    private func realRouter() throws -> Router {
        Router([
            "/sbin/route -n get default": ok(try fixture("route_default")),
            "/usr/sbin/scutil --nwi": ok(try fixture("scutil_nwi")),
            "/usr/sbin/networksetup -listallhardwareports": ok(try fixture("hardware_ports")),
        ])
    }

    func testSnapshotOnARealMac() async throws {
        let reader = SystemNetworkReader(runner: try realRouter(), dns: FakeDNS(servers: ["192.168.29.1", "192.168.68.1"]))
        let snapshot = try await reader.snapshot()
        let primary = try XCTUnwrap(snapshot.primary)
        XCTAssertEqual(primary.name, "en1")
        XCTAssertEqual(primary.hardwarePort, "Wi-Fi")
        XCTAssertTrue(primary.isWiFi)
        XCTAssertEqual(primary.ipv4Addresses, ["192.168.68.106"])
        XCTAssertEqual(primary.ipv6Addresses, ["fd00:1234:5678:9abc:1111:2222:3333:4444"])
        XCTAssertEqual(primary.isReachable, true)
        XCTAssertEqual(snapshot.gateway, "192.168.68.1")
        XCTAssertEqual(snapshot.dnsServers, ["192.168.29.1", "192.168.68.1"])
        XCTAssertTrue(snapshot.hasDefaultRoute)
        XCTAssertTrue(snapshot.otherInterfaces.isEmpty)
        XCTAssertTrue(snapshot.copyText.contains("Gateway: 192.168.68.1"))
    }

    func testNoDefaultRouteIsAnAnswerNotAnError() async throws {
        let router = Router([
            "/sbin/route -n get default": CommandOutput(stdout: "", stderr: "route: writing to routing socket: not in table", status: 1),
            "/usr/sbin/scutil --nwi": ok("Network information\n\nNo IPv4 states found\nNo IPv6 states found\n\nNetwork interfaces: \n"),
            "/usr/sbin/networksetup -listallhardwareports": ok(try fixture("hardware_ports")),
        ])
        let snapshot = try await SystemNetworkReader(runner: router, dns: FakeDNS(servers: [])).snapshot()
        XCTAssertNil(snapshot.primary)
        XCTAssertFalse(snapshot.hasDefaultRoute)
        XCTAssertEqual(NetworkAssessment.headline(snapshot: snapshot, checks: nil), "Not connected to a network")
    }

    func testNothingReadableIsAnError() async {
        let router = Router([:])
        do { _ = try await SystemNetworkReader(runner: router, dns: FakeDNS(servers: [])).snapshot(); XCTFail("expected throw") }
        catch { XCTAssertTrue(error is NetError) }
    }

    func testChecksPingTheGatewayAndDNSServersOnly() async throws {
        let ping = try fixture("ping_3")
        let router = Router([
            "/sbin/ping -c 3 -t 5 192.168.68.1": ok(ping),
            "/sbin/ping -c 3 -t 5 192.168.29.1": ok(ping.replacingOccurrences(of: "1.1.1.1", with: "192.168.29.1")),
        ])
        let snapshot = NetSnapshot(primary: nil, otherInterfaces: [], gateway: "192.168.68.1",
                                   dnsServers: ["192.168.29.1", "192.168.68.1", "2001:db8::53"], hasDefaultRoute: true)
        let checks = try await SystemNetworkReader(runner: router, dns: FakeDNS(servers: [])).runChecks(for: snapshot)
        guard case .result(let gateway)? = checks.gateway else { return XCTFail("no gateway result") }
        XCTAssertEqual(gateway.host, "192.168.68.1")
        XCTAssertEqual(checks.dnsServers.map(\.host), ["192.168.29.1", "192.168.68.1", "2001:db8::53"])
        guard case .skipped(_, let reason) = checks.dnsServers[2] else { return XCTFail("IPv6 server should be skipped") }
        XCTAssertTrue(reason.contains("IPv6"))
        // Only the gateway and the (deduplicated) DNS servers were ever pinged, and only IPv4 ones.
        let pinged = Set(router.calls.compactMap { $0.last })
        XCTAssertEqual(pinged, ["192.168.68.1", "192.168.29.1"])
        XCTAssertTrue(router.calls.allSatisfy { $0.first == "/sbin/ping" && $0.contains("-c") })
    }

    func testPingRefusesAnythingThatIsNotAnIPv4Literal() async throws {
        let router = Router([:])
        let reader = SystemNetworkReader(runner: router, dns: FakeDNS(servers: []))
        for bad in ["-f", "example.com", "1.1.1.1 -c 1000", ""] {
            guard case .skipped = try await reader.ping(bad) else { return XCTFail("pinged \(bad)") }
        }
        XCTAssertTrue(router.calls.isEmpty)
    }

    func testWiFiUsesSystemProfiler() async throws {
        let router = Router(["/usr/sbin/system_profiler SPAirPortDataType -json": ok(try fixture("wifi_profiler"))])
        let wifi = try await SystemNetworkReader(runner: router, dns: FakeDNS(servers: [])).wifi(interface: "en1")
        XCTAssertEqual(wifi?.signalDBm, -35)
    }
}

final class AssessmentTests: XCTestCase {
    private func snapshot(reachable: String? = "Reachable", route: Bool = true) -> NetSnapshot {
        NetSnapshot(primary: NetInterface(name: "en1", hardwarePort: "Wi-Fi", ipv4Addresses: ["192.168.1.2"], ipv6Addresses: [], reachability: reachable),
                    otherInterfaces: [], gateway: "192.168.1.1", dnsServers: ["192.168.1.1"], hasDefaultRoute: route)
    }

    private func ping(_ host: String, received: Int, avg: Double? = 5) -> PingOutcome {
        .result(PingResult(host: host, transmitted: 3, received: received, lossPercent: Double(3 - received) / 3 * 100,
                           minMilliseconds: avg, averageMilliseconds: avg, maxMilliseconds: avg))
    }

    func testHeadlines() {
        XCTAssertEqual(NetworkAssessment.headline(snapshot: snapshot(), checks: nil), "Connected via Wi-Fi")
        XCTAssertEqual(NetworkAssessment.headline(snapshot: snapshot(route: false), checks: nil), "Connected to Wi-Fi, but there is no route to the internet")
        XCTAssertEqual(NetworkAssessment.headline(snapshot: snapshot(reachable: "Not Reachable"), checks: nil), "macOS reports Wi-Fi as not reachable")
        let healthy = NetworkChecks(gateway: ping("192.168.1.1", received: 3), dnsServers: [ping("192.168.1.1", received: 3)])
        XCTAssertEqual(NetworkAssessment.headline(snapshot: snapshot(), checks: healthy), "Connection looks healthy")
        let routerDown = NetworkChecks(gateway: ping("192.168.1.1", received: 0, avg: nil), dnsServers: [])
        XCTAssertEqual(NetworkAssessment.headline(snapshot: snapshot(), checks: routerDown), "Your router did not answer")
        let dnsDown = NetworkChecks(gateway: ping("192.168.1.1", received: 3), dnsServers: [ping("8.8.8.8", received: 0, avg: nil)])
        XCTAssertEqual(NetworkAssessment.headline(snapshot: snapshot(), checks: dnsDown), "Your DNS servers did not answer")
    }

    func testFindingsKeepFactsAndInferencesApart() {
        let wifi = WiFiInfo(networkName: nil, channel: nil, phyMode: nil, transmitRateMbps: nil, security: nil, signalDBm: -72,
                            noiseDBm: -90, countryCode: nil, isConnected: true)
        let lossy = NetworkChecks(gateway: ping("192.168.1.1", received: 1, avg: 80), dnsServers: [])
        let findings = NetworkAssessment.findings(snapshot: snapshot(), wifi: wifi, checks: lossy)
        XCTAssertTrue(findings.contains { $0.basis == .verified && $0.text.contains("-72 dBm") && $0.text.contains("18 dB") })
        XCTAssertTrue(findings.contains { $0.basis == .verified && $0.text.contains("1 of 3 replies") })
        XCTAssertTrue(findings.contains { $0.basis == .inference && $0.text.contains("weak signal") })
        XCTAssertTrue(findings.contains { $0.basis == .inference && $0.text.contains("slow") })
        XCTAssertTrue(findings.filter { $0.basis == .verified }.allSatisfy { !$0.text.contains("usually") && !$0.text.contains("often") })
    }

    func testNoRepliesIsNeverPresentedAsProofOfAnOutage() {
        let findings = NetworkAssessment.findings(snapshot: snapshot(), wifi: nil,
                                                   checks: NetworkChecks(gateway: ping("192.168.1.1", received: 0, avg: nil), dnsServers: []))
        XCTAssertTrue(findings.contains { $0.basis == .verified && $0.text.contains("no replies") })
        XCTAssertTrue(findings.contains { $0.basis == .inference && $0.text.contains("ignore pings") })
    }
}
