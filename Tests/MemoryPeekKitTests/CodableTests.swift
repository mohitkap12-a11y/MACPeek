import XCTest
import MemoryPeekKit

/// Encodes to JSON and back; the value must survive unchanged so a MacPeek Remote console can read it.
private func assertRoundTrips<T: Codable & Equatable>(_ value: T, file: StaticString = #filePath, line: UInt = #line) throws {
    let data = try JSONEncoder().encode(value)
    XCTAssertEqual(try JSONDecoder().decode(T.self, from: data), value, file: file, line: line)
}

final class CodableTests: XCTestCase {
    func testMemoryValuesRoundTrip() throws {
        let stats = MemoryStats(physicalBytes: 25_769_803_776, pageSize: 16_384, wiredPages: 207_000, compressorPages: 232_000,
                                purgeablePages: 12_000, externalPages: 280_000, internalPages: 610_000,
                                swapUsedBytes: 1_288_490_188, pressure: .warning)
        try assertRoundTrips(stats)
        try assertRoundTrips(MemoryBreakdown(stats))
        try assertRoundTrips(MemoryStats(physicalBytes: 8_589_934_592, pageSize: 16_384, wiredPages: 0, compressorPages: 0,
                                         purgeablePages: 0, externalPages: 0, internalPages: 0, swapUsedBytes: nil, pressure: nil))
        try assertRoundTrips(MemoryStats(physicalBytes: 8_589_934_592, pageSize: 16_384, wiredPages: 1, compressorPages: 2,
                                         purgeablePages: 3, externalPages: 4, internalPages: 5, swapUsedBytes: 1_073_741_824,
                                         pressure: .normal, swapTotalBytes: 2_147_483_648))
        try assertRoundTrips(ProcessMemoryRow(pid: 3120, name: "Xcode", footprintBytes: 4_402_341_478))
    }

    func testSwapTotalIsOptionalOnTheWire() throws {
        let stats = MemoryStats(physicalBytes: 1, pageSize: 1, wiredPages: 0, compressorPages: 0, purgeablePages: 0,
                                externalPages: 0, internalPages: 0, swapUsedBytes: 0, pressure: .normal)
        XCTAssertNil(stats.swapTotalBytes)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: try JSONEncoder().encode(stats)) as? [String: Any])
        json["swapTotalBytes"] = nil
        let decoded = try JSONDecoder().decode(MemoryStats.self, from: try JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded, stats)
    }
}
