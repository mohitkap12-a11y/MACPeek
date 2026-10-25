import XCTest
import EnvPeekKit

/// Encodes to JSON and back; the value must survive unchanged so a MacPeek Remote console can read it.
private func assertRoundTrips<T: Codable & Equatable>(_ value: T, file: StaticString = #filePath, line: UInt = #line) throws {
    let data = try JSONEncoder().encode(value)
    XCTAssertEqual(try JSONDecoder().decode(T.self, from: data), value, file: file, line: line)
}

final class CodableTests: XCTestCase {
    func testEnvironmentRoundTrips() throws {
        try assertRoundTrips(ProcessArguments(executable: "/usr/bin/env", arguments: ["env", "-i"],
                                              environment: [EnvVariable(name: "PATH", value: "/usr/bin:/bin"),
                                                            EnvVariable(name: "PATH", value: "/opt/bin", occurrence: 1)]))
        try assertRoundTrips(ProcessArguments(executable: nil, arguments: [], environment: []))
    }
}
