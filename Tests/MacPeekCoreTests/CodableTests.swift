import XCTest
import MacPeekCore

/// Encodes to JSON and back; the value must survive unchanged so a MacPeek Remote console can read it.
private func assertRoundTrips<T: Codable & Equatable>(_ value: T, file: StaticString = #filePath, line: UInt = #line) throws {
    let data = try JSONEncoder().encode(value)
    XCTAssertEqual(try JSONDecoder().decode(T.self, from: data), value, file: file, line: line)
}

final class CodableTests: XCTestCase {
    func testCatalogRoundTrips() throws {
        try assertRoundTrips(UtilityCatalog.all)
    }

    func testProcessUsageRoundTrips() throws {
        let usage = ProcessUsage(pid: 812, name: "postgres", generation: 3, ageNanoseconds: 9_000_000_000,
                                 cpuTimeNanoseconds: 1_250_000_000, memoryFootprintBytes: 255_852_544,
                                 diskBytesRead: 4_096, diskBytesWritten: 8_192)
        try assertRoundTrips(ProcessUsageSnapshot(usages: [usage], unreadable: 2))
    }

    func testTerminationValuesRoundTrip() throws {
        try assertRoundTrips(ProcessTarget(pid: 48213, processName: "node", startTime: 1_761_390_724.5))
        try assertRoundTrips(ProcessTarget(pid: 1, processName: "launchd", startTime: nil))
        try assertRoundTrips([TerminationResult.terminated, .alreadyExited, .resourceAlreadyReleased, .permissionDenied,
                              .targetChanged, .stillRunning, .failed("kill: operation not permitted")])
        try assertRoundTrips([ResourceCheck.owned(processName: "node"), .gone, .changed, .unavailable("lsof failed")])
        try assertRoundTrips([ReleaseState.released, .takenOver(pid: 9921), .stillHeld])
        try assertRoundTrips([TerminationCapability.canTerminate, .permissionRequired, .protected])
        try assertRoundTrips(GaugeReading(fraction: 0.63, caption: "358 GB free", isAlert: false))
    }
}
