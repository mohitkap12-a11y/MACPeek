import XCTest
import MacPeekCore
import CPUPeekKit
import ProcessPeekKit
import SensorsKit
import VitalsKit
import RemoteCrypto
import RemoteProtocol
@testable import RemoteAgent

/// `sensors.snapshot`, `vitals.history` and `alerts.recent`: what the Mac's own monitor knows, for MacPeek Remote.
final class VitalsAgentTests: XCTestCase {
    private struct Unreadable: Error {}

    private actor Requests {
        private(set) var history: [(Date, Int)] = []
        func add(_ since: Date, _ count: Int) { history.append((since, count)) }
    }

    private static let sensors = SensorSnapshot(temperatures: [TemperatureSensor(name: "pACC MTR Temp Sensor0", group: .cpu, celsius: 48)],
                                                fans: [FanReading(index: 0, rpm: 1100, minimumRPM: 1000, maximumRPM: 4000)],
                                                systemWatts: 9.5)
    private static let alert = AlertEvent(kind: .runawayProcess, time: Date(timeIntervalSince1970: 1_700_000_000),
                                          title: "node has used 99% CPU for 5 min", message: "It may be stuck.", pid: 42,
                                          processName: "node")

    private func handler(_ requests: Requests, historyOn: Bool = true) -> RequestHandler {
        var readers = AgentReaders(
            device: { DeviceInfo(computerName: "Studio", localHostName: "studio", modelIdentifier: nil, macOSVersion: "15.1", bootTime: nil) },
            cpuTopology: { CPUTopology(chip: "M2", logicalCores: 8, groups: []) },
            cpuSnapshot: { throw Unreadable() }, memory: { throw Unreadable() }, processUsage: { throw Unreadable() },
            volumes: { throw Unreadable() }, networkCounters: { throw Unreadable() }, networkSnapshot: { throw Unreadable() },
            ports: { [] }, processes: { ProcessSnapshot(entries: []) }, sleep: { throw Unreadable() })
        readers.sensors = { Self.sensors }
        readers.vitalsHistory = { since, count in
            await requests.add(since, count)
            guard historyOn else { throw RemoteError(.unavailable, "History is turned off on this Mac.") }
            return [VitalsPoint(time: since, span: 10, cpu: 0.5)]
        }
        readers.alerts = { [Self.alert] }
        return RequestHandler(readers: readers, actions: AgentActions(freePort: { _, _ in .terminated }, quitProcess: { _, _ in .terminated }),
                              agentVersion: "0.5.0")
    }

    private func console() -> PairedConsole {
        PairedConsole(identity: DeviceIdentity(name: "Laptop").publicIdentity, role: .viewOnly, pairedAt: Date())
    }

    private let settings = RemoteSettings(isEnabled: true, allowActions: false)

    func testAdvertisedAsReads() async throws {
        let capabilities = try await handler(Requests()).handle(.request(.capabilities), from: console(), settings: settings)
            .response.body(Capabilities.self)
        for operation in [Operation.sensors, .vitalsHistory, .alerts] {
            XCTAssertTrue(capabilities.operations.contains(operation), operation.rawValue)
            XCTAssertFalse(operation.isAction, "a view-only device may read \(operation.rawValue)")
        }
    }

    func testSensorsAndAlerts() async throws {
        let handler = handler(Requests())
        let sensors = try await handler.handle(.request(.sensors), from: console(), settings: settings).response.body(SensorSnapshot.self)
        XCTAssertEqual(sensors, Self.sensors)
        let alerts = try await handler.handle(.request(.alerts), from: console(), settings: settings).response.body([AlertEvent].self)
        XCTAssertEqual(alerts, [Self.alert])
    }

    func testHistoryCapsTheCount() async throws {
        let requests = Requests()
        let handler = handler(requests)
        let since = Date(timeIntervalSince1970: 1_700_000_000)
        let request = try Envelope.request(.vitalsHistory, body: VitalsHistoryRequest(since: since, maximumCount: 1_000_000))
        let points = try await handler.handle(request, from: console(), settings: settings).response.body([VitalsPoint].self)
        XCTAssertEqual(points.count, 1)
        let recorded = await requests.history
        XCTAssertEqual(recorded.first?.0, since)
        XCTAssertEqual(recorded.first?.1, 1_440)
    }

    func testHistoryTurnedOffIsAnError() async throws {
        let request = try Envelope.request(.vitalsHistory, body: VitalsHistoryRequest(since: Date()))
        let response = await handler(Requests(), historyOn: false).handle(request, from: console(), settings: settings).response
        XCTAssertEqual(response.kind, .error)
        XCTAssertEqual(try response.body(RemoteError.self).code, .unavailable)
    }

    func testDefaultsAreUnavailableWithoutTheApp() async throws {
        let readers = AgentReaders(
            device: { DeviceInfo(computerName: "A", localHostName: "a", modelIdentifier: nil, macOSVersion: "15", bootTime: nil) },
            cpuTopology: { CPUTopology(chip: nil, logicalCores: 1, groups: []) },
            cpuSnapshot: { throw Unreadable() }, memory: { throw Unreadable() }, processUsage: { throw Unreadable() },
            volumes: { throw Unreadable() }, networkCounters: { throw Unreadable() }, networkSnapshot: { throw Unreadable() },
            ports: { [] }, processes: { ProcessSnapshot(entries: []) }, sleep: { throw Unreadable() })
        let handler = RequestHandler(readers: readers, actions: AgentActions(freePort: { _, _ in .terminated }, quitProcess: { _, _ in .terminated }),
                                     agentVersion: "0.5.0")
        let response = await handler.handle(.request(.alerts), from: console(), settings: settings).response
        XCTAssertEqual(response.kind, .error)
    }
}
