import XCTest
import GPUPeekKit
@testable import RemoteAgent

final class RefreshingDeviceFactsTests: XCTestCase {
    private final class CountingReader: GPUDeviceFactsReading, @unchecked Sendable {
        var reads = 0
        var names = ["Apple M2 Pro"]
        func facts() -> [GPUDeviceFacts] {
            reads += 1
            return names.map {
                GPUDeviceFacts(name: $0, hasUnifiedMemory: true, recommendedMaxWorkingSetBytes: 1, maxBufferBytes: 1,
                               gpuFamily: nil, supportsMetal3: true, isLowPower: false, isRemovable: false)
            }
        }
    }

    private final class Clock: @unchecked Sendable { var date = Date(timeIntervalSince1970: 0) }

    func testReusesFactsWithinLifetimeAndRereadsAfter() {
        let reader = CountingReader(), clock = Clock()
        let facts = RefreshingDeviceFacts(reader: reader, lifetime: 60, now: { clock.date })
        XCTAssertEqual(facts.facts().map(\.name), ["Apple M2 Pro"])
        clock.date += 30
        reader.names.append("AMD Radeon Pro W6800X")
        XCTAssertEqual(facts.facts().count, 1)
        XCTAssertEqual(reader.reads, 1)
        clock.date += 31
        XCTAssertEqual(facts.facts().map(\.name), ["Apple M2 Pro", "AMD Radeon Pro W6800X"])
        XCTAssertEqual(reader.reads, 2)
    }
}
