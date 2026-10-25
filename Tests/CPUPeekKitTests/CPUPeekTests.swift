import XCTest
import MacPeekCore
@testable import CPUPeekKit

final class CoreUsageTests: XCTestCase {
    private func t(_ user: UInt32, _ system: UInt32, _ idle: UInt32, _ nice: UInt32 = 0) -> CoreTicks {
        CoreTicks(user: user, system: system, idle: idle, nice: nice)
    }

    func testUsageOverTheInterval() throws {
        let usage = try XCTUnwrap(CoreUsage.between([t(0, 0, 0), t(0, 0, 0)], [t(50, 25, 25), t(0, 0, 100)]))
        XCTAssertEqual(usage.perCore[0], 0.75, accuracy: 0.0001)
        XCTAssertEqual(usage.perCore[1], 0, accuracy: 0.0001)
        XCTAssertEqual(usage.total, 0.375, accuracy: 0.0001)
        XCTAssertEqual(usage.user, 0.25, accuracy: 0.0001)
        XCTAssertEqual(usage.system, 0.125, accuracy: 0.0001)
    }

    func testNiceCountsAsUser() throws {
        let usage = try XCTUnwrap(CoreUsage.between([t(0, 0, 0, 0)], [t(0, 0, 50, 50)]))
        XCTAssertEqual(usage.user, 0.5, accuracy: 0.0001)
    }

    func testWrappingCounters() throws {
        let usage = try XCTUnwrap(CoreUsage.between([t(UInt32.max - 9, 0, UInt32.max - 9)], [t(10, 0, 10)]))
        XCTAssertEqual(usage.total, 0.5, accuracy: 0.0001, "32-bit tick counters wrap without producing nonsense")
    }

    func testNothingToCompare() {
        XCTAssertNil(CoreUsage.between([t(0, 0, 0)], [t(1, 1, 1), t(1, 1, 1)]), "core count changed")
        XCTAssertNil(CoreUsage.between([t(5, 5, 5)], [t(5, 5, 5)]), "no time passed")
        XCTAssertNil(CoreUsage.between([], []))
    }
}

final class ProcessCPUSamplerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private let second: UInt64 = 1_000_000_000

    private func u(_ pid: Int, cpu: UInt64, generation: UInt64 = 1) -> ProcessUsage {
        ProcessUsage(pid: pid, name: "p\(pid)", generation: generation, cpuTimeNanoseconds: cpu, memoryFootprintBytes: 0)
    }

    func testFirstSampleOnlySetsABaseline() {
        var sampler = ProcessCPUSampler()
        XCTAssertTrue(sampler.ingest([u(1, cpu: 50 * second)], at: t0).isEmpty)
        XCTAssertTrue(sampler.isBaselineOnly)
    }

    func testPercentOfOneCoreBusiestFirst() {
        var sampler = ProcessCPUSampler()
        _ = sampler.ingest([u(1, cpu: 10 * second), u(2, cpu: 10 * second), u(3, cpu: 5 * second)], at: t0)
        let rows = sampler.ingest([u(1, cpu: 11 * second), u(2, cpu: 13 * second), u(3, cpu: 5 * second)],
                                  at: t0.addingTimeInterval(2))
        XCTAssertFalse(sampler.isBaselineOnly)
        XCTAssertEqual(rows.map(\.pid), [2, 1], "idle processes are not listed")
        XCTAssertEqual(rows[0].percent, 150, accuracy: 0.001, "3 s of CPU in 2 s is 1.5 cores")
        XCTAssertEqual(rows[1].percent, 50, accuracy: 0.001)
    }

    func testReusedPIDAndNewProcessCountOnlyTheirOwnTime() {
        var sampler = ProcessCPUSampler()
        _ = sampler.ingest([u(1, cpu: 100 * second, generation: 1)], at: t0)
        let rows = sampler.ingest([u(1, cpu: 1 * second, generation: 2), u(9, cpu: second / 2)], at: t0.addingTimeInterval(2))
        XCTAssertEqual(rows.first { $0.pid == 1 }?.percent ?? -1, 50, accuracy: 0.001)
        XCTAssertEqual(rows.first { $0.pid == 9 }?.percent ?? -1, 25, accuracy: 0.001)
    }

    func testCounterGoingDownReportsNothing() {
        var sampler = ProcessCPUSampler()
        _ = sampler.ingest([u(1, cpu: 100 * second, generation: 0)], at: t0)
        XCTAssertTrue(sampler.ingest([u(1, cpu: 1 * second, generation: 0)], at: t0.addingTimeInterval(2)).isEmpty)
    }
}

final class CPUTextTests: XCTestCase {
    func testCoresLabel() {
        XCTAssertEqual(CPUTopology(chip: nil, logicalCores: 8, groups: []).coresLabel, "8 cores")
        XCTAssertEqual(CPUTopology(chip: nil, logicalCores: 1, groups: []).coresLabel, "1 core")
        let m = CPUTopology(chip: "Apple M2", logicalCores: 8,
                            groups: [.init(name: "Performance", logicalCores: 4), .init(name: "Efficiency", logicalCores: 4)])
        XCTAssertEqual(m.coresLabel, "4 performance · 4 efficiency")
    }

    func testPercentText() {
        XCTAssertEqual(PercentText.fraction(0.423), "42 %")
        XCTAssertEqual(PercentText.fraction(-1), "0 %")
        XCTAssertEqual(PercentText.ofOneCore(183.4), "183 %")
        XCTAssertEqual(PercentText.ofOneCore(0.44), "0.4 %")
    }

    func testHeadlines() {
        let idle = CPUUsage(total: 0.05, user: 0.03, system: 0.02, perCore: [])
        let busy = CPUUsage(total: 0.9, user: 0.8, system: 0.1, perCore: [])
        let top = ProcessCPURow(pid: 1, name: "Xcode", percent: 300)
        XCTAssertEqual(CPUAssessment.headline(usage: idle, top: top, thermal: .nominal), "CPU is mostly idle")
        XCTAssertEqual(CPUAssessment.headline(usage: busy, top: top, thermal: nil), "CPU is busy. Busiest: Xcode")
        XCTAssertEqual(CPUAssessment.headline(usage: idle, top: top, thermal: .serious), "Your Mac is running hot. Busiest: Xcode")
    }

    func testLauncherSummary() {
        XCTAssertEqual(CPUAssessment.launcherSummary(CPUSnapshot(cores: [], loadAverage: [2.345, 1, 1], thermal: .fair)), "Load 2.3")
        XCTAssertEqual(CPUAssessment.launcherSummary(CPUSnapshot(cores: [], loadAverage: [2, 1, 1], thermal: .critical)), "Running hot")
        XCTAssertNil(CPUAssessment.launcherSummary(CPUSnapshot(cores: [], loadAverage: [], thermal: nil)))
    }
}

final class LiveCPUReaderTests: XCTestCase {
    func testReadsEveryCoreAndTwoSnapshotsGiveUsage() throws {
        let reader = SystemCPUReader()
        let first: CPUSnapshot
        do { first = try reader.snapshot() } catch { throw XCTSkip("CPU load unavailable here: \(error)") }
        XCTAssertFalse(first.cores.isEmpty)
        XCTAssertGreaterThan(reader.topology().logicalCores, 0)
        // Spin briefly so some ticks pass.
        let end = Date().addingTimeInterval(0.2)
        var x = 0
        while Date() < end { x &+= 1 }
        let second = try reader.snapshot()
        if let usage = CoreUsage.between(first.cores, second.cores) {
            XCTAssertTrue((0...1).contains(usage.total), "\(usage.total)")
        }
        XCTAssertNotEqual(x, -1)
    }
}
