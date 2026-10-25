import XCTest
import SleepPeekKit

/// Encodes to JSON and back; the value must survive unchanged so a MacPeek Remote console can read it.
private func assertRoundTrips<T: Codable & Equatable>(_ value: T, file: StaticString = #filePath, line: UInt = #line) throws {
    let data = try JSONEncoder().encode(value)
    XCTAssertEqual(try JSONDecoder().decode(T.self, from: data), value, file: file, line: line)
}

final class CodableTests: XCTestCase {
    func testParsedSleepValuesRoundTrip() throws {
        let report = AssertionParser.parse(try fixture("assertions"))
        XCTAssertFalse(report.systemStatus.isEmpty)
        try assertRoundTrips(report)
        try assertRoundTrips(PowerSettingsParser.parse(try fixture("pmset_g")))
        try assertRoundTrips(SleepLogParser.parse(try fixture("sleep_log")))
    }

    func testSystemStatusKeepsItsOrderOnTheWire() throws {
        let report = AssertionReport(systemStatus: [(name: "PreventUserIdleSystemSleep", count: 1), (name: "ApplePushServiceTask", count: 0)],
                                     assertions: [], kernelAssertions: [])
        let decoded = try JSONDecoder().decode(AssertionReport.self, from: try JSONEncoder().encode(report))
        XCTAssertEqual(decoded.systemStatus.map(\.name), ["PreventUserIdleSystemSleep", "ApplePushServiceTask"])
        XCTAssertEqual(decoded.count("PreventUserIdleSystemSleep"), 1)
    }
}
