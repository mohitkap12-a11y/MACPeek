import XCTest
import DNSPeekKit

/// Encodes to JSON and back; the value must survive unchanged so a MacPeek Remote console can read it.
private func assertRoundTrips<T: Codable & Equatable>(_ value: T, file: StaticString = #filePath, line: UInt = #line) throws {
    let data = try JSONEncoder().encode(value)
    XCTAssertEqual(try JSONDecoder().decode(T.self, from: data), value, file: file, line: line)
}

final class CodableTests: XCTestCase {
    func testDNSValuesRoundTrip() throws {
        let configuration = ScutilDNSParser.parse(try fixture("scutil_dns"))
        XCTAssertFalse(configuration.resolvers.isEmpty)
        try assertRoundTrips(configuration)
        try assertRoundTrips(DigParser.outcome(output: try fixture("dig_answer"), status: 0))
        try assertRoundTrips(DigParser.outcome(output: try fixture("dig_timeout"), status: 9))
    }
}
