import XCTest
import CPUPeekKit

/// Encodes to JSON and back; the value must survive unchanged so a MacPeek Remote console can read it.
private func assertRoundTrips<T: Codable & Equatable>(_ value: T, file: StaticString = #filePath, line: UInt = #line) throws {
    let data = try JSONEncoder().encode(value)
    XCTAssertEqual(try JSONDecoder().decode(T.self, from: data), value, file: file, line: line)
}

final class CodableTests: XCTestCase {
    func testCPUValuesRoundTrip() throws {
        try assertRoundTrips(CPUTopology(chip: "Apple M4 Pro", logicalCores: 14,
                                         groups: [.init(name: "Performance", logicalCores: 10), .init(name: "Efficiency", logicalCores: 4)]))
        try assertRoundTrips(CPUTopology(chip: nil, logicalCores: 8, groups: []))
        let snapshot = CPUSnapshot(cores: [CoreTicks(user: 4_294_967_000, system: 12, idle: 900, nice: 0)],
                                   loadAverage: [4.12, 3.8, 3.55], thermal: .serious)
        try assertRoundTrips(snapshot)
        try assertRoundTrips(CPUSnapshot(cores: [], loadAverage: [], thermal: nil))
        try assertRoundTrips(CPUUsage(total: 0.38, user: 0.29, system: 0.09, perCore: [0.76, 0.05]))
        try assertRoundTrips(ProcessCPURow(pid: 48213, name: "node", percent: 182.4))
    }
}
