import XCTest
import NetPeekKit

/// Encodes to JSON and back; the value must survive unchanged so a MacPeek Remote console can read it.
private func assertRoundTrips<T: Codable & Equatable>(_ value: T, file: StaticString = #filePath, line: UInt = #line) throws {
    let data = try JSONEncoder().encode(value)
    XCTAssertEqual(try JSONDecoder().decode(T.self, from: data), value, file: file, line: line)
}

final class CodableTests: XCTestCase {
    func testNetworkValuesRoundTrip() throws {
        try assertRoundTrips(try XCTUnwrap(PingParser.parse(try fixture("ping_3"), host: "1.1.1.1")))
        try assertRoundTrips(try XCTUnwrap(WiFiParser.parse(try fixture("wifi_profiler"), interface: "en1")))
    }
}
