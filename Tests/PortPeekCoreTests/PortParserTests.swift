import XCTest
@testable import PortPeekCore

func fixture(_ name: String) throws -> String {
    guard let url = Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures") else {
        throw NSError(domain: "fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing \(name)"])
    }
    return try String(contentsOf: url, encoding: .utf8)
}

final class PortParserTests: XCTestCase {
    func testTCPIPv4() throws {
        let ports = PortParser.parse(try fixture("tcp_ipv4"))
        XCTAssertEqual(ports.count, 1)
        let p = try XCTUnwrap(ports.first)
        XCTAssertEqual(p.port, 3000)
        XCTAssertEqual(p.protocolType, .tcp)
        XCTAssertEqual(p.address, "127.0.0.1")
        XCTAssertEqual(p.processName, "node")
        XCTAssertEqual(p.pid, 18432)
        XCTAssertEqual(p.user, "mohit")
        XCTAssertEqual(p.state, .listen)
        XCTAssertEqual(p.endpoint, "127.0.0.1:3000")
    }

    func testIPv6BracketsStripped() throws {
        let ports = PortParser.parse(try fixture("tcp_ipv6"))
        XCTAssertEqual(ports.count, 2)
        let v6 = try XCTUnwrap(ports.first { $0.address == "::1" })
        XCTAssertEqual(v6.port, 5432)
        XCTAssertEqual(v6.endpoint, "[::1]:5432")
    }

    func testUDPSkipsUnboundAndConnected() throws {
        let ports = PortParser.parse(try fixture("udp"))
        XCTAssertEqual(ports.count, 1) // *:5353 v4 and v6 share an id and are merged
        XCTAssertEqual(ports[0].protocolType, .udp)
        XCTAssertEqual(ports[0].port, 5353)
        XCTAssertNil(ports[0].state)
    }

    func testMultiplePortsSameProcessAndNonListenSkipped() throws {
        let ports = PortParser.parse(try fixture("multiple_ports"))
        XCTAssertEqual(ports.map(\.port), [5173, 24678])
        XCTAssertTrue(ports.allSatisfy { $0.pid == 19283 })
    }

    func testWildcardAddresses() throws {
        let ports = PortParser.parse(try fixture("wildcard_addresses"))
        XCTAssertEqual(ports.count, 2) // dual-stack *:6379 de-duplicated
        XCTAssertEqual(ports.first { $0.port == 6379 }?.address, "*")
        XCTAssertEqual(ports.first { $0.port == 6380 }?.address, "::")
    }

    func testMalformedOutputDoesNotCrashAndYieldsNothing() throws {
        XCTAssertEqual(PortParser.parse(try fixture("malformed")), [])
    }

    func testEmptyOutput() {
        XCTAssertEqual(PortParser.parse(""), [])
        XCTAssertEqual(PortParser.parse("\n\n"), [])
    }

    func testMixedProcessesAndEscapedNames() throws {
        let ports = PortParser.parse(try fixture("mixed_processes"))
        XCTAssertEqual(ports.map(\.port), [3001, 8080, 8888, 9222])
        XCTAssertEqual(ports.first { $0.port == 9222 }?.processName, "Google Chrome Helper")
        XCTAssertEqual(ports.first { $0.port == 3001 }?.user, "other")
    }

    func testResultsSortedByPort() throws {
        let text = try fixture("mixed_processes") + (try fixture("tcp_ipv4"))
        let ports = PortParser.parse(text).map(\.port)
        XCTAssertEqual(ports, ports.sorted())
    }
}
