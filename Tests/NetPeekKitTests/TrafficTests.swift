import XCTest
@testable import NetPeekKit

final class TrafficTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_761_000_000)

    func testFirstReadingIsOnlyABaseline() {
        var sampler = TrafficSampler()
        XCTAssertTrue(sampler.isBaselineOnly)
        XCTAssertNil(sampler.ingest([InterfaceCounters(name: "en0", bytesIn: 100, bytesOut: 50)], at: start))
        XCTAssertFalse(sampler.isBaselineOnly)
    }

    func testRatesAreBytesPerSecondAndTotalsSkipVirtualInterfaces() throws {
        var sampler = TrafficSampler()
        _ = sampler.ingest([InterfaceCounters(name: "en0", bytesIn: 1_000, bytesOut: 500),
                            InterfaceCounters(name: "utun3", bytesIn: 0, bytesOut: 0),
                            InterfaceCounters(name: "lo0", bytesIn: 0, bytesOut: 0)], at: start)
        let rates = try XCTUnwrap(sampler.ingest([InterfaceCounters(name: "en0", bytesIn: 9_000, bytesOut: 2_500),
                                                  InterfaceCounters(name: "utun3", bytesIn: 4_000, bytesOut: 4_000),
                                                  InterfaceCounters(name: "lo0", bytesIn: 800, bytesOut: 800)],
                                                 at: start.addingTimeInterval(2)))
        XCTAssertEqual(rates.intervalSeconds, 2)
        XCTAssertEqual(rates.interfaces.map(\.name), ["en0", "lo0", "utun3"])
        XCTAssertEqual(rates.interfaces.first { $0.name == "en0" }?.inBytesPerSecond, 4_000)
        XCTAssertEqual(rates.interfaces.first { $0.name == "en0" }?.outBytesPerSecond, 1_000)
        XCTAssertEqual(rates.inBytesPerSecond, 4_000)
        XCTAssertEqual(rates.outBytesPerSecond, 1_000)
    }

    func testThirtyTwoBitWrapIsCountedAndAResetIsNot() {
        XCTAssertEqual(TrafficSampler.delta(100, since: 4_294_967_196), 200)
        XCTAssertEqual(TrafficSampler.delta(10, since: 5_000_000_000), 0)
        XCTAssertEqual(TrafficSampler.delta(7, since: 7), 0)
    }

    func testNewInterfaceWaitsForItsOwnBaselineAndGoneOnesDrop() throws {
        var sampler = TrafficSampler()
        _ = sampler.ingest([InterfaceCounters(name: "en0", bytesIn: 0, bytesOut: 0)], at: start)
        let rates = try XCTUnwrap(sampler.ingest([InterfaceCounters(name: "en1", bytesIn: 999, bytesOut: 999)],
                                                 at: start.addingTimeInterval(1)))
        XCTAssertTrue(rates.interfaces.isEmpty)
        let next = try XCTUnwrap(sampler.ingest([InterfaceCounters(name: "en1", bytesIn: 1_999, bytesOut: 999)],
                                                at: start.addingTimeInterval(2)))
        XCTAssertEqual(next.interfaces.map(\.inBytesPerSecond), [1_000])
    }

    func testClockThatDidNotMoveRestartsTheBaseline() {
        var sampler = TrafficSampler()
        _ = sampler.ingest([InterfaceCounters(name: "en0", bytesIn: 0, bytesOut: 0)], at: start)
        XCTAssertNil(sampler.ingest([InterfaceCounters(name: "en0", bytesIn: 50, bytesOut: 0)], at: start))
        XCTAssertNil(sampler.ingest([InterfaceCounters(name: "en0", bytesIn: 60, bytesOut: 0)], at: start.addingTimeInterval(-1)))
    }

    func testVirtualInterfaceNames() {
        for name in ["lo0", "utun4", "ipsec0", "gif0", "stf0", "awdl0", "llw0", "bridge0", "ap1", "anpi0"] {
            XCTAssertTrue(InterfaceCounters(name: name, bytesIn: 0, bytesOut: 0).isVirtual, name)
        }
        for name in ["en0", "en7"] {
            XCTAssertFalse(InterfaceCounters(name: name, bytesIn: 0, bytesOut: 0).isVirtual, name)
        }
    }

    func testReaderReturnsCounters() throws {
        #if os(Linux)
        let counters = try SystemInterfaceCountersReader().read()
        XCTAssertTrue(counters.contains { $0.name == "lo" })
        #endif
    }

    #if os(Linux)
    func testProcNetDevParsing() {
        let text = """
        Inter-|   Receive                                                |  Transmit
         face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
            lo:  123456     100    0    0    0     0          0         0   123456     100    0    0    0     0       0          0
          eth0: 98765432  70000    0    0    0     0          0         0  1234567    9000    0    0    0     0       0          0
        """
        XCTAssertEqual(SystemInterfaceCountersReader.parse(text),
                       [InterfaceCounters(name: "lo", bytesIn: 123_456, bytesOut: 123_456),
                        InterfaceCounters(name: "eth0", bytesIn: 98_765_432, bytesOut: 1_234_567)])
    }
    #endif

    func testThroughputRoundTrips() throws {
        let value = NetworkThroughput(interfaces: [InterfaceThroughput(name: "en0", inBytesPerSecond: 4_800_000, outBytesPerSecond: 1_200_000,
                                                                       isVirtual: false)], intervalSeconds: 2)
        XCTAssertEqual(try JSONDecoder().decode(NetworkThroughput.self, from: try JSONEncoder().encode(value)), value)
        let counters = InterfaceCounters(name: "en0", bytesIn: 1, bytesOut: 2)
        XCTAssertEqual(try JSONDecoder().decode(InterfaceCounters.self, from: try JSONEncoder().encode(counters)), counters)
    }
}
