import XCTest
import MemoryPeekKit
import CPUPeekKit
@testable import VitalsKit

final class AlertEngineTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let gib: UInt64 = 1 << 30

    private func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    private func process(_ pid: Int, cpu: Double? = nil, memory: UInt64 = 0, name: String = "worker", generation: UInt64 = 1)
        -> ProcessObservation {
        ProcessObservation(pid: pid, generation: generation, name: name, cpuPercent: cpu, footprintBytes: memory)
    }

    func testRunawayProcessAlertsOnceAfterItsMinutes() {
        var engine = AlertEngine()
        let settings = AlertSettings()
        var events: [AlertEvent] = []
        for minute in stride(from: 0.0, through: 10, by: 0.5) {
            events += engine.evaluate(AlertObservation(time: at(minute), processes: [process(1, cpu: 99)]), settings: settings)
        }
        XCTAssertEqual(events.count, 1, "one alert per episode")
        XCTAssertEqual(events.first?.kind, .runawayProcess)
        XCTAssertEqual(events.first?.time, at(5))
        XCTAssertEqual(events.first?.pid, 1)
    }

    func testABreakRestartsTheRunawayClock() {
        var engine = AlertEngine()
        var events: [AlertEvent] = []
        for minute in stride(from: 0.0, through: 4, by: 1) {
            events += engine.evaluate(AlertObservation(time: at(minute), processes: [process(1, cpu: 99)]), settings: .default)
        }
        events += engine.evaluate(AlertObservation(time: at(4.5), processes: [process(1, cpu: 10)]), settings: .default)
        for minute in stride(from: 5.0, through: 9, by: 1) {
            events += engine.evaluate(AlertObservation(time: at(minute), processes: [process(1, cpu: 99)]), settings: .default)
        }
        XCTAssertTrue(events.isEmpty)
    }

    func testTicksWithoutAProcessScanKeepTheClockRunning() {
        var engine = AlertEngine()
        var events = engine.evaluate(AlertObservation(time: at(0), processes: [process(1, cpu: 99)]), settings: .default)
        events += engine.evaluate(AlertObservation(time: at(3), processes: nil), settings: .default)
        events += engine.evaluate(AlertObservation(time: at(5), processes: [process(1, cpu: 99)]), settings: .default)
        XCTAssertEqual(events.map(\.kind), [.runawayProcess])
    }

    func testAReusedPIDIsADifferentProcess() {
        var engine = AlertEngine()
        var events = engine.evaluate(AlertObservation(time: at(0), processes: [process(1, cpu: 99, generation: 1)]), settings: .default)
        events += engine.evaluate(AlertObservation(time: at(5), processes: [process(1, cpu: 99, generation: 2)]), settings: .default)
        XCTAssertTrue(events.isEmpty)
    }

    func testTurningProcessRulesOffForgetsTheirEpisodes() {
        var engine = AlertEngine()
        var off = AlertSettings()
        off.runawayEnabled = false
        off.leakEnabled = false
        var events = engine.evaluate(AlertObservation(time: at(0), processes: [process(1, cpu: 99)]), settings: .default)
        // Rules off: the monitor stops scanning and passes no processes.
        events += engine.evaluate(AlertObservation(time: at(3), processes: nil), settings: off)
        events += engine.evaluate(AlertObservation(time: at(5), processes: [process(1, cpu: 99)]), settings: .default)
        XCTAssertTrue(events.isEmpty, "the clock restarted when the rules came back on")
        events += engine.evaluate(AlertObservation(time: at(10), processes: [process(1, cpu: 99)]), settings: .default)
        XCTAssertEqual(events.map(\.kind), [.runawayProcess])
    }

    func testIgnoredProcessesNeverAlert() {
        var engine = AlertEngine()
        var settings = AlertSettings()
        settings.ignoredProcesses = ["Xcode"]
        var events: [AlertEvent] = []
        for minute in stride(from: 0.0, through: 10, by: 1) {
            events += engine.evaluate(AlertObservation(time: at(minute), processes: [process(1, cpu: 400, name: "xcode")]), settings: settings)
        }
        XCTAssertTrue(events.isEmpty)
    }

    func testTheSameAlertWaitsForTheRepeatInterval() {
        var engine = AlertEngine()
        var events: [AlertEvent] = []
        func run(from: Double, to: Double, cpu: Double) {
            for minute in stride(from: from, through: to, by: 1) {
                events += engine.evaluate(AlertObservation(time: at(minute), processes: [process(1, cpu: cpu)]), settings: .default)
            }
        }
        run(from: 0, to: 6, cpu: 99)
        run(from: 7, to: 7, cpu: 1)
        run(from: 8, to: 20, cpu: 99)
        XCTAssertEqual(events.count, 1, "cleared and true again within an hour: no second alert")
        run(from: 21, to: 21, cpu: 1)
        run(from: 80, to: 90, cpu: 99)
        XCTAssertEqual(events.count, 2)
    }

    func testSteadyMemoryGrowthAlerts() {
        var engine = AlertEngine()
        var events: [AlertEvent] = []
        for minute in 0...15 {
            let memory = gib + UInt64(minute) * (gib / 5)
            events += engine.evaluate(AlertObservation(time: at(Double(minute)), processes: [process(7, memory: memory)]),
                                      settings: .default)
        }
        XCTAssertEqual(events.map(\.kind), [.memoryGrowth])
        XCTAssertEqual(events.first?.processName, "worker")
    }

    func testMemoryThatComesAndGoesIsNotALeak() {
        var engine = AlertEngine()
        var events: [AlertEvent] = []
        for minute in 0...15 {
            let memory = minute == 8 ? gib : gib + UInt64(minute) * (gib / 4)
            events += engine.evaluate(AlertObservation(time: at(Double(minute)), processes: [process(7, memory: memory)]),
                                      settings: .default)
        }
        XCTAssertTrue(events.isEmpty)
    }

    func testCriticalPressureAlertsAtOnceAndWarningAfterItsMinutes() {
        var engine = AlertEngine()
        XCTAssertEqual(engine.evaluate(AlertObservation(time: at(0), pressure: .critical), settings: .default).map(\.isCritical), [true])
        var other = AlertEngine()
        var events: [AlertEvent] = []
        for minute in 0...10 {
            events += other.evaluate(AlertObservation(time: at(Double(minute)), pressure: .warning), settings: .default)
        }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.time, at(10))
    }

    func testSwapGrowthWithinTheWindow() {
        var engine = AlertEngine()
        XCTAssertTrue(engine.evaluate(AlertObservation(time: at(0), swapUsedBytes: gib), settings: .default).isEmpty)
        XCTAssertTrue(engine.evaluate(AlertObservation(time: at(10), swapUsedBytes: 2 * gib), settings: .default).isEmpty)
        XCTAssertEqual(engine.evaluate(AlertObservation(time: at(20), swapUsedBytes: 3 * gib), settings: .default).map(\.kind),
                       [.swapGrowth])
    }

    func testSustainedNetwork() {
        var engine = AlertEngine()
        var events: [AlertEvent] = []
        for minute in 0...5 {
            events += engine.evaluate(AlertObservation(time: at(Double(minute)), networkBytesPerSecond: 8_000_000), settings: .default)
        }
        XCTAssertEqual(events.map(\.kind), [.sustainedNetwork])
    }

    func testThermalAndDisabledAlerts() {
        var engine = AlertEngine()
        var settings = AlertSettings()
        XCTAssertEqual(engine.evaluate(AlertObservation(time: at(0), thermal: .serious), settings: settings).map(\.kind), [.thermal])
        settings.thermalEnabled = false
        var quiet = AlertEngine()
        XCTAssertTrue(quiet.evaluate(AlertObservation(time: at(0), thermal: .critical), settings: settings).isEmpty)
    }

    func testSettingsFromAnOlderVersionKeepNewDefaults() throws {
        let data = Data(#"{"runawayPercent": 150}"#.utf8)
        let settings = try JSONDecoder().decode(AlertSettings.self, from: data)
        XCTAssertEqual(settings.runawayPercent, 150)
        XCTAssertTrue(settings.leakEnabled)
        XCTAssertEqual(settings.networkMinutes, AlertSettings.default.networkMinutes)
    }

    func testSteadyGrowthShape() {
        XCTAssertTrue(AlertEngine.isSteadyGrowth([10, 20, 19, 30]))
        XCTAssertFalse(AlertEngine.isSteadyGrowth([10, 20, 5, 30]))
    }
}
