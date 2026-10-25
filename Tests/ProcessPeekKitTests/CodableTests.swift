import XCTest
import ProcessPeekKit

/// Encodes to JSON and back; the value must survive unchanged so a MacPeek Remote console can read it.
private func assertRoundTrips<T: Codable & Equatable>(_ value: T, file: StaticString = #filePath, line: UInt = #line) throws {
    let data = try JSONEncoder().encode(value)
    XCTAssertEqual(try JSONDecoder().decode(T.self, from: data), value, file: file, line: line)
}

final class CodableTests: XCTestCase {
    func testParsedProcessesRoundTrip() throws {
        let entries = PSParser.parse(try fixture("ps_sample"))
        XCTAssertFalse(entries.isEmpty)
        try assertRoundTrips(entries)
    }
}
