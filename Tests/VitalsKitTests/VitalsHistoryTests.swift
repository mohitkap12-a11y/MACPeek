import XCTest
import MemoryPeekKit
@testable import VitalsKit

final class VitalsHistoryTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 999_999_960) // a whole minute

    func testSamplesInOneSlotAreAveraged() {
        var history = VitalsHistory()
        history.record(VitalsSample(time: t0, cpu: 0.2, pressure: .normal))
        history.record(VitalsSample(time: t0.addingTimeInterval(4), cpu: 0.4, pressure: .warning))
        history.record(VitalsSample(time: t0.addingTimeInterval(10), cpu: 1))
        let points = history.points(since: t0)
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[0].cpu ?? 0, 0.3, accuracy: 0.0001)
        XCTAssertEqual(points[0].pressure, .warning, "the worst pressure in the slot")
        XCTAssertEqual(points[1].cpu, 1, "the open slot is included")
    }

    func testMissingValuesStayMissing() {
        var history = VitalsHistory()
        history.record(VitalsSample(time: t0, cpu: 0.5))
        XCTAssertNil(history.points(since: t0).first?.temperature)
    }

    func testOldPointsAreCompactedThenDropped() {
        var history = VitalsHistory()
        // Two hours of 10-second samples at 50 % CPU.
        for second in stride(from: 0, to: 2 * 3600, by: 10) {
            history.record(VitalsSample(time: t0.addingTimeInterval(TimeInterval(second)), cpu: 0.5))
        }
        let now = t0.addingTimeInterval(2 * 3600)
        history.prune(now: now)
        let points = history.points(since: t0, maximumCount: 10_000)
        let coarse = points.filter { $0.span == VitalsHistory.coarseSlot }
        let fine = points.filter { $0.span == VitalsHistory.fineSlot }
        XCTAssertEqual(coarse.count, 60, "the first hour is one-minute points")
        XCTAssertGreaterThanOrEqual(fine.count, 355)
        XCTAssertLessThanOrEqual(fine.count, 361)
        XCTAssertEqual(coarse.first?.cpu ?? 0, 0.5, accuracy: 0.0001)

        history.prune(now: now.addingTimeInterval(24 * 3600))
        XCTAssertTrue(history.points(since: .distantPast).isEmpty, "nothing older than a day is kept")
    }

    func testPruningTwiceDoesNotChangeCoarsePoints() {
        var history = VitalsHistory()
        for second in stride(from: 0, to: 3 * 3600, by: 10) {
            history.record(VitalsSample(time: t0.addingTimeInterval(TimeInterval(second)), cpu: Double(second % 60) / 60))
        }
        let now = t0.addingTimeInterval(3 * 3600)
        history.prune(now: now)
        let once = history.points(since: .distantPast, maximumCount: 10_000)
        history.prune(now: now)
        XCTAssertEqual(history.points(since: .distantPast, maximumCount: 10_000), once)
    }

    func testPointsAreMergedToTheRequestedCount() {
        var history = VitalsHistory()
        for second in stride(from: 0, to: 1000, by: 10) {
            history.record(VitalsSample(time: t0.addingTimeInterval(TimeInterval(second)), cpu: 0.25))
        }
        let points = history.points(since: t0, maximumCount: 10)
        XCTAssertLessThanOrEqual(points.count, 10)
        XCTAssertEqual(points[0].cpu ?? 0, 0.25, accuracy: 0.0001)
    }

    func testAClockThatWentBackDropsTheFuture() {
        var history = VitalsHistory()
        history.record(VitalsSample(time: t0.addingTimeInterval(100), cpu: 1))
        history.record(VitalsSample(time: t0.addingTimeInterval(200), cpu: 1))
        history.record(VitalsSample(time: t0, cpu: 0))
        let points = history.points(since: .distantPast)
        XCTAssertEqual(points.map(\.cpu), [0])
    }

    func testTheFileRoundTrips() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vitals-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let file = VitalsHistoryFile(url: url)
        var history = VitalsHistory()
        let now = Date()
        history.record(VitalsSample(time: now, cpu: 0.4, memoryUsed: 0.6, pressure: .warning, swapUsedBytes: 42, networkIn: 1,
                                    networkOut: 2, gpu: 0.1, temperature: 55, power: 12))
        try file.save(history)
        let loaded = file.load(now: now)
        XCTAssertEqual(loaded.points(since: .distantPast), history.points(since: .distantPast))
        XCTAssertTrue(VitalsHistoryFile(url: url.appendingPathExtension("missing")).load().isEmpty)
    }
}

final class MenuBarReadoutTests: XCTestCase {
    func testPercentKeepsItsWidth() {
        XCTAssertEqual(MenuBarReadout.percent(0.07), "  7%")
        XCTAssertEqual(MenuBarReadout.percent(0.423), " 42%")
        XCTAssertEqual(MenuBarReadout.percent(1.2), "100%")
        XCTAssertEqual(MenuBarReadout.percent(nil), "  –%")
    }

    func testRates() {
        XCTAssertEqual(MenuBarReadout.rate(0), "0K")
        XCTAssertEqual(MenuBarReadout.rate(512 * 1024), "512K")
        XCTAssertEqual(MenuBarReadout.rate(1.3 * 1024 * 1024), "1.3M")
        XCTAssertEqual(MenuBarReadout.rate(34 * 1024 * 1024), "34M")
        XCTAssertEqual(MenuBarReadout.rate(2 * 1024 * 1024 * 1024), "2.0G")
    }

    func testItemsAndLevels() {
        let sample = VitalsSample(time: Date(), cpu: 0.95, memoryUsed: 0.5, pressure: .warning, networkIn: 1024, networkOut: 0,
                                  temperature: 88)
        let items = MenuBarReadout.items(for: [.cpu, .memory, .network, .temperature, .gpu], sample: sample)
        XCTAssertEqual(items.map(\.level), [.critical, .warning, .normal, .warning, .normal])
        XCTAssertEqual(items[2].value, "↓1K ↑0K")
        XCTAssertEqual(items[3].value, "88°")
        XCTAssertEqual(items[4].value, "  –%", "no GPU reading yet")
        XCTAssertTrue(MenuBarReadout.spokenText(items).hasPrefix("CPU 95%"))
    }
}

final class ProcessGroupingTests: XCTestCase {
    private struct Row: Sendable {
        let name: String
        let cpu: Double
    }

    func testFamilies() {
        XCTAssertEqual(ProcessGrouping.family(of: "Google Chrome Helper (Renderer)")?.name, "Google Chrome")
        XCTAssertEqual(ProcessGrouping.family(of: "Microsoft Edge Helper (GPU)")?.name, "Microsoft Edge")
        XCTAssertEqual(ProcessGrouping.family(of: "com.apple.WebKit.WebContent")?.name, "Safari and web views")
        XCTAssertEqual(ProcessGrouping.family(of: "plugin-container")?.name, "Firefox")
        XCTAssertEqual(ProcessGrouping.family(of: "Slack Helper (Renderer)")?.name, "Slack")
        XCTAssertEqual(ProcessGrouping.family(of: "Code Helper")?.name, "Code")
        XCTAssertNotNil(ProcessGrouping.family(of: "Google Chrome Helper (Renderer)")?.tabHint)
        XCTAssertNil(ProcessGrouping.family(of: "Help Viewer"))
        XCTAssertNil(ProcessGrouping.family(of: "HelperTool"))
        XCTAssertNil(ProcessGrouping.family(of: "Finder"))
    }

    func testGroupsAreOrderedByTotalAndSinglesStayAlone() {
        let rows = [Row(name: "Google Chrome Helper (Renderer)", cpu: 30), Row(name: "Finder", cpu: 50),
                    Row(name: "Google Chrome", cpu: 5), Row(name: "Google Chrome Helper (GPU)", cpu: 25),
                    Row(name: "Slack Helper", cpu: 1), Row(name: "Slack", cpu: 1), Row(name: "Code Helper", cpu: 2)]
        let groups = ProcessGrouping.group(rows, name: \.name, value: \.cpu)
        XCTAssertEqual(groups.map(\.title), ["Google Chrome", "", "Slack", ""])
        XCTAssertEqual(groups[0].total, 60)
        XCTAssertEqual(groups[0].items.count, 3)
        XCTAssertEqual(groups[1].items.first?.name, "Finder")
        XCTAssertEqual(groups[3].items.first?.name, "Code Helper", "a lone helper is not a group")
    }
}
