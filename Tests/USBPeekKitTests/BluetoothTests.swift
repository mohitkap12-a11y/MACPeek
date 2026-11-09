import XCTest
@testable import USBPeekKit
import MacPeekCore

final class BluetoothTests: XCTestCase {
    func testDevicesAndBatteries() throws {
        let report = try XCTUnwrap(BluetoothParser.parse(try fixture("bluetooth")))
        XCTAssertEqual(report.poweredOn, true)
        XCTAssertEqual(report.connected.map(\.name), ["AirPods Pro", "MX Master 3S"])
        XCTAssertEqual(report.paired.map(\.name), ["Kitchen Speaker"])
        let pods = report.connected[0]
        XCTAssertEqual(pods.batteryLabel, "L 100% · R 98% · Case 34%")
        XCTAssertEqual(pods.lowestBattery, 98)
        XCTAssertEqual(pods.kind, "Headphones")
        XCTAssertEqual(report.connected[1].batteryLabel, "15%")
        XCTAssertEqual(report.lowBattery.map(\.name), ["MX Master 3S"])
        XCTAssertFalse(report.paired[0].hasBattery)
        XCTAssertNil(BluetoothParser.parse("{}"))
    }

    func testAddressesNeverEnterTheModel() throws {
        let report = try XCTUnwrap(BluetoothParser.parse(try fixture("bluetooth")))
        let json = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)
        XCTAssertFalse(json.contains("xx:xx"))
        XCTAssertEqual(try JSONDecoder().decode(BluetoothReport.self, from: Data(json.utf8)), report)
    }

    func testReader() async throws {
        let runner = ScriptedRunner(["SPBluetoothDataType": ok(try fixture("bluetooth"))])
        let report = try await SystemBluetoothReader(runner: runner).bluetooth()
        XCTAssertEqual(report.devices.count, 3)
        XCTAssertEqual(runner.calls.first?.1, ["SPBluetoothDataType", "-json"])
    }
}
