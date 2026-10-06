import XCTest
@testable import PortPeekKit
@testable import MacPeekCore

final class SearchTests: XCTestCase {
    let ports = [
        PortInfo(port: 3000, protocolType: .tcp, address: "127.0.0.1", processName: "node", pid: 18432),
        PortInfo(port: 5173, protocolType: .tcp, address: "*", processName: "node", pid: 19283),
        PortInfo(port: 5432, protocolType: .tcp, address: "::1", processName: "postgres", pid: 921),
        PortInfo(port: 5353, protocolType: .udp, address: "*", processName: "mDNSResponder", pid: 301),
    ]

    func testEmptyQueryReturnsAll() {
        XCTAssertEqual(PortSearch.filter(ports, query: "  ").count, 4)
    }

    func testByPort() {
        XCTAssertEqual(PortSearch.filter(ports, query: "3000").map(\.port), [3000])
    }

    func testPartialPort() {
        XCTAssertEqual(Set(PortSearch.filter(ports, query: "54").map(\.port)), [5432])
        XCTAssertEqual(Set(PortSearch.filter(ports, query: "53").map(\.port)), [5353])
    }

    func testByProcessCaseInsensitive() {
        XCTAssertEqual(PortSearch.filter(ports, query: "NODE").map(\.port), [3000, 5173])
    }

    func testByPID() {
        XCTAssertEqual(PortSearch.filter(ports, query: "18432").map(\.pid), [18432])
    }

    func testByAddressAndProtocol() {
        XCTAssertEqual(PortSearch.filter(ports, query: "127.0.0").map(\.port), [3000])
        XCTAssertEqual(PortSearch.filter(ports, query: "udp").map(\.port), [5353])
    }

    func testMultipleTokensAreAnded() {
        XCTAssertEqual(PortSearch.filter(ports, query: "node 5173").map(\.port), [5173])
        XCTAssertEqual(PortSearch.filter(ports, query: "node postgres"), [])
    }

    func testExactPortRanksFirst() {
        let list = [
            PortInfo(port: 8080, protocolType: .tcp, address: "*", processName: "a", pid: 3000),
            PortInfo(port: 3000, protocolType: .tcp, address: "*", processName: "b", pid: 5),
        ]
        XCTAssertEqual(PortSearch.filter(list, query: "3000").map(\.port), [3000, 8080])
    }

    func testNoMatchGivesEmpty() {
        XCTAssertEqual(PortSearch.filter(ports, query: "zzz"), [])
    }
}
