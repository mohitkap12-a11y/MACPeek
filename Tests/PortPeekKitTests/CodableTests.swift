import XCTest
import PortPeekKit

/// Encodes to JSON and back; the value must survive unchanged so a MacPeek Remote console can read it.
private func assertRoundTrips<T: Codable & Equatable>(_ value: T, file: StaticString = #filePath, line: UInt = #line) throws {
    let data = try JSONEncoder().encode(value)
    XCTAssertEqual(try JSONDecoder().decode(T.self, from: data), value, file: file, line: line)
}

final class CodableTests: XCTestCase {
    func testParsedPortsRoundTrip() throws {
        for name in ["multiple_ports", "tcp_ipv6", "udp", "wildcard_addresses"] {
            let ports = PortParser.parse(try fixture(name))
            XCTAssertFalse(ports.isEmpty, name)
            try assertRoundTrips(ports)
        }
    }
}
