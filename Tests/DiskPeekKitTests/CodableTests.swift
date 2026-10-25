import XCTest
import DiskPeekKit

/// Encodes to JSON and back; the value must survive unchanged so a MacPeek Remote console can read it.
private func assertRoundTrips<T: Codable & Equatable>(_ value: T, file: StaticString = #filePath, line: UInt = #line) throws {
    let data = try JSONEncoder().encode(value)
    XCTAssertEqual(try JSONDecoder().decode(T.self, from: data), value, file: file, line: line)
}

final class CodableTests: XCTestCase {
    func testDiskValuesRoundTrip() throws {
        try assertRoundTrips(DiskReadResult(counters: [DiskCounters(pid: 611, name: "mds_stores", bytesRead: 10, bytesWritten: 20,
                                                                   generation: 4, ageNanoseconds: 5)], unreadable: 1))
        try assertRoundTrips(DiskActivity(pid: 611, name: "mds_stores", readBytesPerSecond: 12_400_000, writeBytesPerSecond: 3_100_000,
                                          readSinceOpened: 1_000, writtenSinceOpened: 2_000))
        try assertRoundTrips(VolumeCapacity(name: "Macintosh HD", path: "/", totalBytes: 994_662_584_320, strictlyFreeBytes: 300_000_000_000,
                                            availableForImportantUsageBytes: 358_000_000_000, isRoot: true, isInternal: true, isRemovable: false))
        try assertRoundTrips(VolumeCapacity(name: "Backup", path: "/Volumes/Backup", totalBytes: 2_000_000_000_000, strictlyFreeBytes: 1,
                                            availableForImportantUsageBytes: nil, isRoot: false, isInternal: nil, isRemovable: nil))
    }
}
