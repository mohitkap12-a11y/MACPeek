import XCTest
import DisplayPeekKit

/// Encodes to JSON and back; the value must survive unchanged so a MacPeek Remote console can read it.
private func assertRoundTrips<T: Codable & Equatable>(_ value: T, file: StaticString = #filePath, line: UInt = #line) throws {
    let data = try JSONEncoder().encode(value)
    XCTAssertEqual(try JSONDecoder().decode(T.self, from: data), value, file: file, line: line)
}

final class CodableTests: XCTestCase {
    func testDisplayReportRoundTrips() throws {
        let report = try DisplayParser.parse(try fixture("mac_mini_one_display"))
        XCTAssertFalse(report.displays.isEmpty)
        try assertRoundTrips(report)
    }
}
