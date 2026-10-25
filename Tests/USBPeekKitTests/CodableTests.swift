import XCTest
import USBPeekKit

/// Encodes to JSON and back; the value must survive unchanged so a MacPeek Remote console can read it.
private func assertRoundTrips<T: Codable & Equatable>(_ value: T, file: StaticString = #filePath, line: UInt = #line) throws {
    let data = try JSONEncoder().encode(value)
    XCTAssertEqual(try JSONDecoder().decode(T.self, from: data), value, file: file, line: line)
}

final class CodableTests: XCTestCase {
    func testParsedUSBValuesRoundTrip() throws {
        let buses = IORegUSBParser.parse(try fixture("mac_mini_ioreg_usb"))
        XCTAssertFalse(buses.isEmpty)
        try assertRoundTrips(buses)
        try assertRoundTrips(try XCTUnwrap(ThunderboltParser.parse(try fixture("mac_mini_thunderbolt"))))
    }
}
