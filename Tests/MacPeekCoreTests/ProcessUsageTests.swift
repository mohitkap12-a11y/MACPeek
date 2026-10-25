import XCTest
@testable import MacPeekCore

final class ByteCountTextTests: XCTestCase {
    func testMemoryUsesBinaryUnits() {
        XCTAssertEqual(ByteCountText.memory(0), "0 B")
        XCTAssertEqual(ByteCountText.memory(512), "512 B")
        XCTAssertEqual(ByteCountText.memory(1_536), "1.5 KB")
        XCTAssertEqual(ByteCountText.memory(17_179_869_184), "16.0 GB")
        XCTAssertEqual(ByteCountText.memory(150 * 1024 * 1024), "150 MB")
        XCTAssertEqual(ByteCountText.binary(-5), "0 B")
    }

    func testStorageUsesDecimalUnitsLikeFinder() {
        XCTAssertEqual(ByteCountText.storage(1_000_000_000_000), "1.0 TB")
        XCTAssertEqual(ByteCountText.storage(494_384_795_648), "494 GB")
        XCTAssertEqual(ByteCountText.storage(12_300_000_000), "12.3 GB")
        XCTAssertEqual(ByteCountText.storage(-5), "0 B")
    }

    func testRoundsBeforeChoosingTheUnit() {
        XCTAssertEqual(ByteCountText.storage(99_970_000_000), "100 GB", "not 100.0 GB")
        XCTAssertEqual(ByteCountText.storage(999_700), "1.0 MB", "not 1000 KB")
        XCTAssertEqual(ByteCountText.storage(999_600_000_000), "1.0 TB", "not 1000 GB")
        XCTAssertEqual(ByteCountText.binary(1023.7), "1.0 KB", "not 1024 B")
        XCTAssertEqual(ByteCountText.memory(UInt64(9.996 * 1024 * 1024 * 1024)), "10.0 GB")
    }
}

final class ProcessUsageReaderTests: XCTestCase {
    func testCancellationFlag() {
        let flag = CancellationFlag()
        XCTAssertFalse(flag.isCancelled)
        flag.cancel()
        XCTAssertTrue(flag.isCancelled)
    }

    func testACancelledScanStops() throws {
        do {
            _ = try SystemProcessUsageReader().read(isCancelled: { true })
            XCTFail("a cancelled scan must not complete")
        } catch is CancellationError {
        } catch {
            throw XCTSkip("per-process usage unavailable here: \(error)")
        }
    }

    func testReadsThisProcess() throws {
        let snapshot: ProcessUsageSnapshot
        do { snapshot = try SystemProcessUsageReader().read() } catch { throw XCTSkip("per-process usage unavailable here: \(error)") }
        let me = Int(ProcessInfo.processInfo.processIdentifier)
        let own = try XCTUnwrap(snapshot.usages.first { $0.pid == me }, "the current process is always readable")
        XCTAssertGreaterThan(own.memoryFootprintBytes, 0)
        XCTAssertGreaterThan(own.cpuTimeNanoseconds, 0)
        // CPU time is converted from Mach ticks: a test process has used far less than an hour.
        XCTAssertLessThan(own.cpuTimeNanoseconds, 3_600 * 1_000_000_000)
        // The test process is younger than a day, so its age is known and plausible.
        if let age = own.ageNanoseconds { XCTAssertLessThan(age, 86_400 * 1_000_000_000) }
    }

    func testNamesAreReusedAcrossScans() throws {
        let reader = SystemProcessUsageReader()
        let first: ProcessUsageSnapshot
        do { first = try reader.read() } catch { throw XCTSkip("per-process usage unavailable here: \(error)") }
        let second = try reader.read()
        let me = Int(ProcessInfo.processInfo.processIdentifier)
        XCTAssertEqual(first.usages.first { $0.pid == me }?.name, second.usages.first { $0.pid == me }?.name)
    }
}

final class ProcessCounterSamplerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private let second: UInt64 = 1_000_000_000

    private func s(_ pid: Int, _ value: UInt64, generation: UInt64 = 1, age: UInt64? = nil) -> ProcessCounterSampler.Sample {
        ProcessCounterSampler.Sample(pid: pid, generation: generation, ageNanoseconds: age, counters: [value])
    }

    func testFirstSampleIsABaseline() {
        var sampler = ProcessCounterSampler()
        XCTAssertNil(sampler.ingest([s(1, 10)], at: t0))
        XCTAssertTrue(sampler.isBaselineOnly)
    }

    func testDifferencesForTheSameProcess() throws {
        var sampler = ProcessCounterSampler()
        _ = sampler.ingest([s(1, 10)], at: t0)
        let interval = try XCTUnwrap(sampler.ingest([s(1, 25)], at: t0.addingTimeInterval(2)))
        XCTAssertEqual(interval.seconds, 2, accuracy: 0.0001)
        XCTAssertEqual(interval.deltas[1], .continued([15]))
    }

    func testAnOldProcessMissingFromTheLastSampleIsNotChargedItsLifetime() throws {
        var sampler = ProcessCounterSampler()
        _ = sampler.ingest([], at: t0)
        // Running for an hour with 600 s of CPU, unreadable in the previous scan.
        let interval = try XCTUnwrap(sampler.ingest([s(1, 600 * second, age: 3_600 * second)], at: t0.addingTimeInterval(2)))
        XCTAssertEqual(interval.deltas[1], .rebaselined)
        XCTAssertNil(interval.deltas[1]?.values)
    }

    func testAProcessThatStartedInsideTheIntervalCountsEverything() throws {
        var sampler = ProcessCounterSampler()
        _ = sampler.ingest([], at: t0)
        let interval = try XCTUnwrap(sampler.ingest([s(7, 500, age: 1 * second)], at: t0.addingTimeInterval(2)))
        XCTAssertEqual(interval.deltas[7], .started([500]))
    }

    func testUnknownAgeIsTreatedAsABaseline() throws {
        var sampler = ProcessCounterSampler()
        _ = sampler.ingest([], at: t0)
        let interval = try XCTUnwrap(sampler.ingest([s(7, 500)], at: t0.addingTimeInterval(2)))
        XCTAssertEqual(interval.deltas[7], .rebaselined)
    }

    func testReusedPIDAndCountersGoingDown() throws {
        var sampler = ProcessCounterSampler()
        _ = sampler.ingest([s(1, 100, generation: 1), s(2, 100, generation: 0)], at: t0)
        let interval = try XCTUnwrap(sampler.ingest([s(1, 5, generation: 2), s(2, 5, generation: 0)], at: t0.addingTimeInterval(2)))
        XCTAssertEqual(interval.deltas[1], .started([5]), "a new start time is a new process")
        XCTAssertEqual(interval.deltas[2], .rebaselined, "lower counters with no start time to explain them")
    }

    func testNoTimePassed() {
        var sampler = ProcessCounterSampler()
        _ = sampler.ingest([s(1, 10)], at: t0)
        XCTAssertNil(sampler.ingest([s(1, 20)], at: t0))
    }
}
