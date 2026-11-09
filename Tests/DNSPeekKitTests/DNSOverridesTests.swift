import XCTest
@testable import DNSPeekKit

final class DNSOverridesTests: XCTestCase {
    func testHostsFile() throws {
        let entries = HostsFileParser.parse(try fixture("etc_hosts"))
        XCTAssertEqual(entries.count, 5)
        XCTAssertEqual(entries.filter(\.isDefault).count, 3)
        let custom = entries.filter { !$0.isDefault }
        XCTAssertEqual(custom.map(\.address), ["127.0.0.1", "10.0.0.5"])
        XCTAssertEqual(custom[0].names, ["api.example.com", "www.example.com"])
        XCTAssertEqual(custom[0].line, 10)
    }

    func testResolverFile() {
        let file = ResolverFileParser.parse(domain: "test", text: "# dnsmasq\nnameserver 127.0.0.1\nport 5353\nsearch_order 1\ntimeout 5\n")
        XCTAssertEqual(file.nameservers, ["127.0.0.1"])
        XCTAssertEqual(file.port, 5353)
        XCTAssertEqual(file.searchOrder, 1)
        XCTAssertEqual(file.otherSettings, ["timeout 5"])
    }

    func testExplainAndReaderFromFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let resolver = dir.appendingPathComponent("resolver")
        try FileManager.default.createDirectory(at: resolver, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try fixture("etc_hosts").write(to: dir.appendingPathComponent("hosts"), atomically: true, encoding: .utf8)
        try "nameserver 127.0.0.1\nport 5353\n".write(to: resolver.appendingPathComponent("test"), atomically: true, encoding: .utf8)
        try "nameserver 100.100.100.100\n".write(to: resolver.appendingPathComponent("tail1234.ts.net"), atomically: true, encoding: .utf8)

        let overrides = FileDNSOverridesReader(hostsPath: dir.appendingPathComponent("hosts").path, resolverDirectory: resolver.path).overrides()
        XCTAssertNil(overrides.hostsNote)
        XCTAssertEqual(overrides.customHostsEntries.count, 2)
        XCTAssertEqual(overrides.resolverFiles.map(\.domain), ["tail1234.ts.net", "test"])
        XCTAssertTrue(overrides.hasOverrides)
        XCTAssertEqual(overrides.explain(name: "API.example.com.").count, 1)
        XCTAssertTrue(overrides.explain(name: "api.example.com")[0].contains("line 10"))
        XCTAssertEqual(overrides.explain(name: "app.test"), ["/etc/resolver/test sends lookups for *.test to 127.0.0.1 on port 5353."])
        XCTAssertEqual(overrides.explain(name: "nas.tail1234.ts.net").count, 1)
        XCTAssertTrue(overrides.explain(name: "apple.com").isEmpty)
        XCTAssertTrue(overrides.explain(name: "latest").isEmpty, "a domain is not matched by a suffix that is not a label")
        XCTAssertEqual(try JSONDecoder().decode(DNSOverrides.self, from: JSONEncoder().encode(overrides)), overrides)

        let missing = FileDNSOverridesReader(hostsPath: "/nonexistent/hosts", resolverDirectory: "/nonexistent/resolver").overrides()
        XCTAssertNotNil(missing.hostsNote)
        XCTAssertTrue(missing.resolverFiles.isEmpty)
        XCTAssertNil(missing.resolverNote, "no /etc/resolver directory is normal")
    }
}
