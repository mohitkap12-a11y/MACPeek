import XCTest
@testable import MacPeekCore

final class ByteCountTextTests: XCTestCase {
    func testMemoryUsesBinaryUnits() {
        XCTAssertEqual(ByteCountText.memory(0), "0 B")
        XCTAssertEqual(ByteCountText.memory(512), "512 B")
        XCTAssertEqual(ByteCountText.memory(1_536), "1.50 KB")
        XCTAssertEqual(ByteCountText.memory(17_179_869_184), "16.0 GB")
        XCTAssertEqual(ByteCountText.memory(150 * 1024 * 1024), "150 MB")
    }

    func testStorageUsesDecimalUnitsLikeFinder() {
        XCTAssertEqual(ByteCountText.storage(1_000_000_000_000), "1.00 TB")
        XCTAssertEqual(ByteCountText.storage(494_384_795_648), "494 GB")
        XCTAssertEqual(ByteCountText.storage(12_300_000_000), "12.3 GB")
        XCTAssertEqual(ByteCountText.storage(-5), "0 B")
    }
}

final class ProcessUsageReaderTests: XCTestCase {
    func testCancellationFlag() {
        let flag = ProcessScanCancellation()
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
    }
}
