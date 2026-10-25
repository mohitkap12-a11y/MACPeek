import XCTest
import FileLockPeekKit

/// Encodes to JSON and back; the value must survive unchanged so a MacPeek Remote console can read it.
private func assertRoundTrips<T: Codable & Equatable>(_ value: T, file: StaticString = #filePath, line: UInt = #line) throws {
    let data = try JSONEncoder().encode(value)
    XCTAssertEqual(try JSONDecoder().decode(T.self, from: data), value, file: file, line: line)
}

final class CodableTests: XCTestCase {
    func testParsedHoldersRoundTrip() throws {
        for name in ["file_multi_holders", "dir_scan", "kinds"] {
            let holders = FileHolderParser.parse(try fixture(name))
            XCTAssertFalse(holders.isEmpty, name)
            try assertRoundTrips(holders)
        }
    }
}
