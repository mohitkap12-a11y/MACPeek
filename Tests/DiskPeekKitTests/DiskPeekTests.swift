import XCTest
@testable import DiskPeekKit

final class DiskIOSamplerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    private func c(_ pid: Int, read: UInt64, write: UInt64, name: String = "p") -> DiskCounters {
        DiskCounters(pid: pid, name: name + String(pid), bytesRead: read, bytesWritten: write)
    }

    func testFirstSampleOnlySetsABaseline() {
        var sampler = DiskIOSampler()
        XCTAssertTrue(sampler.isBaselineOnly)
        XCTAssertTrue(sampler.ingest([c(1, read: 5_000, write: 5_000)], at: t0).isEmpty)
        XCTAssertTrue(sampler.isBaselineOnly, "still waiting for a second sample")
    }

    func testRatesAreDeltasOverTheInterval() throws {
        var sampler = DiskIOSampler()
        _ = sampler.ingest([c(1, read: 1_000, write: 0)], at: t0)
        let result = sampler.ingest([c(1, read: 5_000, write: 2_000)], at: t0.addingTimeInterval(2))
        XCTAssertFalse(sampler.isBaselineOnly)
        let a = try XCTUnwrap(result.first)
        XCTAssertEqual(a.readBytesPerSecond, 2_000, accuracy: 0.001)
        XCTAssertEqual(a.writeBytesPerSecond, 1_000, accuracy: 0.001)
        XCTAssertEqual(a.readSinceOpened, 4_000)
        XCTAssertEqual(a.writtenSinceOpened, 2_000)

        let next = sampler.ingest([c(1, read: 5_000, write: 2_500)], at: t0.addingTimeInterval(3))
        let b = try XCTUnwrap(next.first)
        XCTAssertEqual(b.readBytesPerSecond, 0, accuracy: 0.001)
        XCTAssertEqual(b.writeBytesPerSecond, 500, accuracy: 0.001)
        XCTAssertEqual(b.writtenSinceOpened, 2_500, "totals accumulate across samples")
    }

    func testOldActivityBeforeOpeningIsNotCounted() {
        var sampler = DiskIOSampler()
        _ = sampler.ingest([c(1, read: 9_000_000, write: 9_000_000)], at: t0)
        let result = sampler.ingest([c(1, read: 9_000_000, write: 9_000_000)], at: t0.addingTimeInterval(2))
        XCTAssertTrue(result.isEmpty, "a process that did nothing since DiskPeek opened is not listed")
    }

    func testCounterGoingDownMeansTheCounterBelongsToANewProcess() throws {
        var sampler = DiskIOSampler()
        _ = sampler.ingest([c(1, read: 10_000, write: 10_000)], at: t0)
        _ = sampler.ingest([c(1, read: 12_000, write: 10_000)], at: t0.addingTimeInterval(2))
        let reused = sampler.ingest([c(1, read: 100, write: 0), c(2, read: 0, write: 0)], at: t0.addingTimeInterval(4))
        XCTAssertTrue(reused.allSatisfy { $0.readBytesPerSecond >= 0 && $0.writeBytesPerSecond >= 0 })
        XCTAssertTrue(reused.isEmpty, "nothing negative or absurd is reported for a reused PID")
        let after = sampler.ingest([c(1, read: 600, write: 0)], at: t0.addingTimeInterval(6))
        XCTAssertEqual(try XCTUnwrap(after.first).readSinceOpened, 500, "the new process starts from its own baseline")
    }

    func testAReusedPIDWithHigherCountersIsStillANewProcess() throws {
        var sampler = DiskIOSampler()
        func g(_ pid: Int, read: UInt64, write: UInt64, generation: UInt64) -> DiskCounters {
            DiskCounters(pid: pid, name: "p\(pid)", bytesRead: read, bytesWritten: write, generation: generation)
        }
        _ = sampler.ingest([g(1, read: 1_000, write: 0, generation: 111)], at: t0)
        let first = sampler.ingest([g(1, read: 2_000, write: 0, generation: 111)], at: t0.addingTimeInterval(2))
        XCTAssertEqual(try XCTUnwrap(first.first).readSinceOpened, 1_000)

        // A different process (new start time) now has PID 1 and has already read more than the old one had.
        let reused = sampler.ingest([g(1, read: 50_000, write: 0, generation: 222)], at: t0.addingTimeInterval(4))
        let row = try XCTUnwrap(reused.first)
        XCTAssertEqual(row.readSinceOpened, 50_000, "the totals belong to the new process alone, not old + new")
        XCTAssertEqual(row.readBytesPerSecond, 25_000, accuracy: 0.001, "it started inside the interval, so all of it happened there")

        let next = sampler.ingest([g(1, read: 51_000, write: 0, generation: 222)], at: t0.addingTimeInterval(5))
        XCTAssertEqual(try XCTUnwrap(next.first).readSinceOpened, 51_000)
    }

    func testAProcessThatAppearsBetweenSamplesCountsEverythingItHasDone() throws {
        var sampler = DiskIOSampler()
        _ = sampler.ingest([c(1, read: 0, write: 0)], at: t0)
        let result = sampler.ingest([c(1, read: 0, write: 0), c(7, read: 4_000, write: 0)], at: t0.addingTimeInterval(2))
        let new = try XCTUnwrap(result.first { $0.pid == 7 })
        XCTAssertEqual(new.readBytesPerSecond, 2_000, accuracy: 0.001)
    }

    func testExitedProcessesDisappear() {
        var sampler = DiskIOSampler()
        _ = sampler.ingest([c(1, read: 0, write: 0), c(2, read: 0, write: 0)], at: t0)
        _ = sampler.ingest([c(1, read: 10, write: 0), c(2, read: 10, write: 0)], at: t0.addingTimeInterval(1))
        let result = sampler.ingest([c(1, read: 20, write: 0)], at: t0.addingTimeInterval(2))
        XCTAssertEqual(result.map(\.pid), [1])
    }

    func testSorting() {
        let slow = DiskActivity(pid: 1, name: "slow", readBytesPerSecond: 10, writeBytesPerSecond: 0, readSinceOpened: 9_000, writtenSinceOpened: 0)
        let fast = DiskActivity(pid: 2, name: "fast", readBytesPerSecond: 500, writeBytesPerSecond: 500, readSinceOpened: 10, writtenSinceOpened: 10)
        XCTAssertEqual(DiskIOSampler.sorted([slow, fast], by: .rate).map(\.name), ["fast", "slow"])
        XCTAssertEqual(DiskIOSampler.sorted([slow, fast], by: .total).map(\.name), ["slow", "fast"])
    }

    func testSampleAtTheSameInstantDoesNotDivideByZero() {
        var sampler = DiskIOSampler()
        _ = sampler.ingest([c(1, read: 0, write: 0)], at: t0)
        XCTAssertTrue(sampler.ingest([c(1, read: 100, write: 0)], at: t0).isEmpty)
    }
}

final class ByteFormattingTests: XCTestCase {
    func testSizes() {
        XCTAssertEqual(ByteSize.label(0), "0 B")
        XCTAssertEqual(ByteSize.label(512), "512 B")
        XCTAssertEqual(ByteSize.label(1_536), "1.5 KB")
        XCTAssertEqual(ByteSize.label(150 * 1024 * 1024), "150 MB")
        XCTAssertEqual(ByteSize.label(3.0 * 1024 * 1024 * 1024), "3.0 GB")
        XCTAssertEqual(ByteSize.label(-5), "0 B")
    }

    func testRates() {
        XCTAssertEqual(ByteRate.label(1_500_000), "1.4 MB/s")
        XCTAssertEqual(ByteRate.label(0), "0 B/s")
    }
}

final class LiveDiskReaderTests: XCTestCase {
    func testACancelledScanStopsInsteadOfRunningToTheEnd() {
        XCTAssertThrowsError(try SystemDiskIOReader().read(isCancelled: { true })) { error in
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
    }

    func testCancellationFlag() {
        let flag = CancellationFlag()
        XCTAssertFalse(flag.isCancelled)
        flag.cancel()
        XCTAssertTrue(flag.isCancelled)
    }

    func testReadsCountersIncludingThisProcess() throws {
        let result: DiskReadResult
        do { result = try SystemDiskIOReader().read() } catch { throw XCTSkip("disk counters unavailable here: \(error)") }
        XCTAssertFalse(result.counters.isEmpty)
        let me = Int(ProcessInfo.processInfo.processIdentifier)
        let own = try XCTUnwrap(result.counters.first { $0.pid == me }, "the current process is always readable")
        XCTAssertFalse(own.name.isEmpty)
    }
}
