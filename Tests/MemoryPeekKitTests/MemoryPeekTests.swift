import XCTest
import MacPeekCore
@testable import MemoryPeekKit

private let gib: UInt64 = 1024 * 1024 * 1024
private let page: UInt64 = 16_384

/// 16 GB Mac: 4 GB app (5 GB internal − 1 GB purgeable), 2 GB wired, 1 GB compressed, 6 GB cached (5 GB file-backed +
/// 1 GB purgeable), so 3 GB free.
private func stats(pressure: MemoryPressure? = .normal, swapUsed: UInt64? = 0, physical: UInt64 = 16 * gib) -> MemoryStats {
    let pages = { (bytes: UInt64) in bytes / page }
    return MemoryStats(physicalBytes: physical, pageSize: page, freePages: pages(3 * gib), activePages: 0, inactivePages: 0,
                       speculativePages: 0, wiredPages: pages(2 * gib), compressorPages: pages(1 * gib),
                       purgeablePages: pages(1 * gib), externalPages: pages(5 * gib), internalPages: pages(5 * gib),
                       swapUsedBytes: swapUsed, swapTotalBytes: swapUsed.map { _ in 2 * gib },
                       pressure: pressure, availablePercent: 60)
}

final class MemoryBreakdownTests: XCTestCase {
    func testSplitsMemoryLikeActivityMonitor() {
        let b = MemoryBreakdown(stats())
        XCTAssertEqual(b.physical, 16 * gib)
        XCTAssertEqual(b.app, 4 * gib, "app memory excludes purgeable pages")
        XCTAssertEqual(b.wired, 2 * gib)
        XCTAssertEqual(b.compressed, 1 * gib)
        XCTAssertEqual(b.cachedFiles, 6 * gib, "file-backed plus purgeable")
        XCTAssertEqual(b.used, 7 * gib)
        XCTAssertEqual(b.free, 3 * gib)
    }

    func testNeverGoesNegative() {
        let s = MemoryStats(physicalBytes: gib, pageSize: page, freePages: 0, activePages: 0, inactivePages: 0,
                            speculativePages: 0, wiredPages: gib / page, compressorPages: gib / page, purgeablePages: 10,
                            externalPages: 0, internalPages: 2, swapUsedBytes: nil, swapTotalBytes: nil,
                            pressure: nil, availablePercent: nil)
        let b = MemoryBreakdown(s)
        XCTAssertEqual(b.app, 0, "purgeable larger than internal does not underflow")
        XCTAssertEqual(b.free, 0, "more accounted than installed does not underflow")
    }
}

final class MemoryPressureTests: XCTestCase {
    func testSysctlLevels() {
        XCTAssertEqual(MemoryPressure(sysctlLevel: 1), .normal)
        XCTAssertEqual(MemoryPressure(sysctlLevel: 2), .warning)
        XCTAssertEqual(MemoryPressure(sysctlLevel: 4), .critical)
        XCTAssertNil(MemoryPressure(sysctlLevel: 0))
        XCTAssertNil(MemoryPressure(sysctlLevel: 3))
    }
}

final class MemoryAssessmentTests: XCTestCase {
    func testNormalPressureIsFineEvenWithSwap() {
        let a = MemoryAssessment(stats: stats(pressure: .normal, swapUsed: 2 * gib))
        XCTAssertEqual(a.tone, .good)
        XCTAssertEqual(a.headline, "Memory is fine")
        XCTAssertTrue(a.detail.contains { $0.contains("2.00 GB") && $0.contains("normal") }, "\(a.detail)")
    }

    func testWarningAndCritical() {
        XCTAssertEqual(MemoryAssessment(stats: stats(pressure: .warning)).tone, .warning)
        let critical = MemoryAssessment(stats: stats(pressure: .critical, swapUsed: 3 * gib))
        XCTAssertEqual(critical.tone, .critical)
        XCTAssertTrue(critical.detail.contains { $0.contains("slower than RAM") }, "\(critical.detail)")
    }

    func testUnknownPressureNeverClaimsAllIsWell() {
        let a = MemoryAssessment(stats: stats(pressure: nil))
        XCTAssertEqual(a.tone, .unknown)
        XCTAssertFalse(a.headline.contains("fine"))
        XCTAssertNil(MemoryAssessment.launcherSummary(stats(pressure: nil)))
    }

    func testNoSwapLineWithoutSwap() {
        let a = MemoryAssessment(stats: stats(swapUsed: 0))
        XCTAssertFalse(a.detail.contains { $0.contains("swap") })
    }

    func testLauncherSummary() {
        XCTAssertEqual(MemoryAssessment.launcherSummary(stats(pressure: .warning)), "Pressure: Warning")
    }

    func testTopProcessesLargestFirstWithStableTies() {
        let usages = [
            ProcessUsage(pid: 3, name: "c", cpuTimeNanoseconds: 0, memoryFootprintBytes: 100),
            ProcessUsage(pid: 1, name: "a", cpuTimeNanoseconds: 0, memoryFootprintBytes: 500),
            ProcessUsage(pid: 2, name: "b", cpuTimeNanoseconds: 0, memoryFootprintBytes: 100),
            ProcessUsage(pid: 4, name: "d", cpuTimeNanoseconds: 0, memoryFootprintBytes: 0),
        ]
        let rows = MemoryAssessment.topProcesses(usages, limit: 3)
        XCTAssertEqual(rows.map(\.pid), [1, 2, 3])
        XCTAssertFalse(MemoryAssessment.topProcesses(usages).contains { $0.pid == 4 }, "zero footprint is not listed")
    }
}

final class LiveMemoryReaderTests: XCTestCase {
    func testReadsPlausibleNumbers() throws {
        let stats: MemoryStats
        do { stats = try SystemMemoryReader().read() } catch { throw XCTSkip("memory statistics unavailable here: \(error)") }
        XCTAssertGreaterThan(stats.physicalBytes, 0)
        XCTAssertGreaterThan(stats.pageSize, 0)
        let b = MemoryBreakdown(stats)
        XCTAssertLessThanOrEqual(b.used, stats.physicalBytes)
    }
}
