import XCTest
@testable import DNSPeekKit
import MacPeekCore

func fixture(_ name: String) throws -> String {
    guard let url = Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures") else {
        throw NSError(domain: "fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing \(name)"])
    }
    return try String(contentsOf: url, encoding: .utf8)
}

final class ScutilDNSParserTests: XCTestCase {
    private func config() throws -> DNSConfiguration { ScutilDNSParser.parse(try fixture("scutil_dns")) }

    func testRealMacTheDefaultResolverIsTheStandardOne() throws {
        let c = try config()
        XCTAssertEqual(c.resolvers.count, 7)
        let primary = try XCTUnwrap(c.primary)
        XCTAssertEqual(primary.number, 1)
        XCTAssertEqual(primary.nameservers, ["192.168.29.1", "192.168.68.1"])
        XCTAssertEqual(primary.interface, "en1")
        XCTAssertEqual(primary.reachability, "Reachable")
        XCTAssertEqual(primary.isReachable, true)
        XCTAssertEqual(primary.kind, .standard)
        XCTAssertEqual(primary.flags, ["Request A records", "Request AAAA records"])
        XCTAssertEqual(c.activeServers, ["192.168.29.1", "192.168.68.1"])
    }

    func testMulticastResolversAreRecognised() throws {
        let c = try config()
        XCTAssertEqual(c.multicastResolvers.count, 6)
        let local = try XCTUnwrap(c.resolvers.first { $0.domain == "local" })
        XCTAssertEqual(local.kind, .multicast)
        XCTAssertEqual(local.options, "mdns")
        XCTAssertEqual(local.timeoutSeconds, 5)
        XCTAssertEqual(local.order, 300_000)
        XCTAssertEqual(local.isReachable, false)
        XCTAssertTrue(c.domainResolvers.isEmpty)
    }

    func testScopedConfigurationIsKeptApart() throws {
        let c = try config()
        XCTAssertEqual(c.scopedResolvers.count, 1)
        XCTAssertTrue(c.scopedResolvers[0].isScoped)
        XCTAssertTrue(c.scopedResolvers[0].flags.contains("Scoped"))
        XCTAssertFalse(c.resolvers.contains { $0.isScoped })
        XCTAssertEqual(Set(c.resolvers.map(\.id)).count, c.resolvers.count)
    }

    func testDomainSpecificResolversAndSearchDomains() {
        let text = """
        DNS configuration

        resolver #1
          search domain[0] : corp.example.com
          search domain[1] : example.com
          nameserver[0] : 10.0.0.2
          if_index : 9 (utun4)
          flags    : Request A records
          reach    : 0x00000002 (Reachable)

        resolver #2
          domain   : internal.example.com
          nameserver[0] : 10.0.0.53
          nameserver[1] : 2001:db8::53
          flags    : Request A records
          reach    : 0x00000002 (Reachable)
          order    : 100
        """
        let c = ScutilDNSParser.parse(text)
        XCTAssertEqual(c.searchDomains, ["corp.example.com", "example.com"])
        XCTAssertEqual(c.activeServers, ["10.0.0.2"])
        XCTAssertEqual(c.primary?.interface, "utun4")
        XCTAssertEqual(c.domainResolvers.map(\.domain), ["internal.example.com"])
        XCTAssertEqual(c.domainResolvers[0].nameservers, ["10.0.0.53", "2001:db8::53"])
        XCTAssertEqual(c.domainResolvers[0].order, 100)
    }

    func testNoDNSAtAll() {
        let c = ScutilDNSParser.parse("No DNS configuration available\n")
        XCTAssertTrue(c.resolvers.isEmpty)
        XCTAssertTrue(c.activeServers.isEmpty)
        XCTAssertNil(c.primary)
        XCTAssertTrue(ScutilDNSParser.parse("").resolvers.isEmpty)
    }

    func testCopyText() throws {
        let text = try config().copyText
        XCTAssertTrue(text.contains("DNS servers in use: 192.168.29.1, 192.168.68.1"))
        XCTAssertTrue(text.contains("Interface: en1"))
    }
}

final class LookupParserTests: XCTestCase {
    func testDSCacheUtilRealOutput() throws {
        XCTAssertEqual(DSCacheUtilParser.addresses(try fixture("dscacheutil_host")), ["2620:149:af0::10", "17.253.144.10"])
        XCTAssertTrue(DSCacheUtilParser.addresses("").isEmpty)
        XCTAssertTrue(DSCacheUtilParser.addresses("name: nothing.invalid\n").isEmpty)
    }

    func testDigAnswered() {
        let out = """
        ;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 12345
        ;; flags: qr rd ra; QUERY: 1, ANSWER: 2, AUTHORITY: 0, ADDITIONAL: 1

        ;; Query time: 17 msec
        ;; SERVER: 192.168.68.1#53(192.168.68.1) (UDP)
        """
        XCTAssertEqual(DigParser.outcome(output: out, status: 0), .answered(queryMilliseconds: 17, status: "NOERROR", answers: 2))
    }

    func testDigNXDomainIsStillAnAnswer() {
        let out = ";; ->>HEADER<<- opcode: QUERY, status: NXDOMAIN, id: 1\n;; flags: qr rd ra; QUERY: 1, ANSWER: 0, AUTHORITY: 1\n;; Query time: 9 msec\n"
        XCTAssertEqual(DigParser.outcome(output: out, status: 0), .answered(queryMilliseconds: 9, status: "NXDOMAIN", answers: 0))
    }

    func testDigTimeout() {
        XCTAssertEqual(DigParser.outcome(output: ";; communications error to 10.0.0.1#53: timed out\n;; no servers could be reached\n", status: 9), .timedOut)
    }

    func testUnrecognisedOutputIsReportedNotGuessed() {
        guard case .unavailable = DigParser.outcome(output: "something else", status: 0) else { return XCTFail() }
        guard case .unavailable = DigParser.outcome(output: "", status: 1) else { return XCTFail() }
    }
}

final class RealDigCaptureTests: XCTestCase {
    func testAnswerFromRealCapture() throws {
        XCTAssertEqual(DigParser.outcome(output: try fixture("dig_answer"), status: 0),
                       .answered(queryMilliseconds: 467, status: "NOERROR", answers: 1))
    }

    func testTimeoutFromRealCapture() throws {
        XCTAssertEqual(DigParser.outcome(output: try fixture("dig_timeout"), status: 9), .timedOut)
    }
}

final class InputValidationTests: XCTestCase {
    func testHostnames() {
        for good in ["apple.com", "a.b-c.example.org", "localhost", "example.com.", "_dmarc.example.com", "xn--bcher-kva.example"] {
            XCTAssertTrue(NetworkInput.isHostname(good), good)
        }
        for bad in ["", "-flag", "--version", "a b.com", "evil.com;rm -rf", "$(whoami).com", "a..b.com", "-a.com", String(repeating: "a", count: 64) + ".com", "http://apple.com"] {
            XCTAssertFalse(NetworkInput.isHostname(bad), bad)
        }
    }

    func testIPAddresses() {
        XCTAssertTrue(NetworkInput.isIPv4("192.168.68.1"))
        XCTAssertTrue(NetworkInput.isIPv6("fe80::1"))
        XCTAssertTrue(NetworkInput.isIPAddress("2001:db8::53"))
        for bad in ["", "999.1.1.1", "1.1.1", "-c", "1.1.1.1 -f", "fe80::1%en0", "example.com"] {
            XCTAssertFalse(NetworkInput.isIPAddress(bad), bad)
        }
    }
}

private final class Recorder: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [(String, [String])] = []
    let handler: @Sendable (String, [String]) throws -> CommandOutput
    init(_ handler: @escaping @Sendable (String, [String]) throws -> CommandOutput) { self.handler = handler }
    var calls: [(String, [String])] { lock.lock(); defer { lock.unlock() }; return _calls }
    private func record(_ e: String, _ a: [String]) { lock.lock(); defer { lock.unlock() }; _calls.append((e, a)) }
    func run(_ executable: String, _ arguments: [String]) async throws -> CommandOutput {
        record(executable, arguments)
        return try handler(executable, arguments)
    }
}

final class DNSServiceTests: XCTestCase {
    func testConfigurationRunsScutil() async throws {
        let text = try fixture("scutil_dns")
        let r = Recorder { _, _ in CommandOutput(stdout: text, stderr: "", status: 0) }
        let c = try await SystemDNSReader(runner: r).configuration()
        XCTAssertEqual(c.activeServers.count, 2)
        XCTAssertEqual(r.calls.first?.0, "/usr/sbin/scutil")
        XCTAssertEqual(r.calls.first?.1, ["--dns"])
    }

    func testLookupUsesDSCacheUtilAndMeasuresTime() async throws {
        let text = try fixture("dscacheutil_host")
        let r = Recorder { _, _ in CommandOutput(stdout: text, stderr: "", status: 0) }
        let result = try await SystemDNSReader(runner: r).lookup(name: "apple.com")
        XCTAssertEqual(result.addresses, ["2620:149:af0::10", "17.253.144.10"])
        XCTAssertGreaterThanOrEqual(result.elapsedMilliseconds, 0)
        XCTAssertEqual(r.calls.first?.0, "/usr/bin/dscacheutil")
        XCTAssertEqual(r.calls.first?.1, ["-q", "host", "-a", "name", "apple.com"])
    }

    func testProbeAsksDigForExactlyThatServerAndName() async throws {
        let r = Recorder { _, _ in CommandOutput(stdout: ";; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 1\n;; flags: qr; QUERY: 1, ANSWER: 1\n;; Query time: 5 msec\n", stderr: "", status: 0) }
        let probe = try await SystemDNSReader(runner: r).probe(server: "192.168.68.1", name: "apple.com")
        XCTAssertEqual(probe.outcome, .answered(queryMilliseconds: 5, status: "NOERROR", answers: 1))
        XCTAssertEqual(r.calls.first?.1, ["@192.168.68.1", "apple.com", "A", "+time=2", "+tries=1"])
    }

    func testInvalidInputNeverReachesATool() async {
        let r = Recorder { _, _ in CommandOutput(stdout: "", stderr: "", status: 0) }
        let reader = SystemDNSReader(runner: r)
        for name in ["-x", "a b", "x;y", ""] {
            do { _ = try await reader.lookup(name: name); XCTFail("accepted \(name)") }
            catch { XCTAssertEqual(error as? DNSError, .invalidName) }
        }
        do { _ = try await reader.probe(server: "--help", name: "apple.com"); XCTFail("accepted a flag as a server") }
        catch { XCTAssertEqual(error as? DNSError, .invalidServer) }
        do { _ = try await reader.probe(server: "1.1.1.1", name: "-bad"); XCTFail("accepted a bad name") }
        catch { XCTAssertEqual(error as? DNSError, .invalidName) }
        XCTAssertTrue(r.calls.isEmpty)
    }

    func testScutilFailureCarriesStderr() async {
        let r = Recorder { _, _ in CommandOutput(stdout: "", stderr: "scutil broke", status: 1) }
        do { _ = try await SystemDNSReader(runner: r).configuration(); XCTFail() }
        catch { XCTAssertEqual(error as? DNSError, .commandFailed("scutil broke")) }
    }
}
