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

    /// system_profiler leaves the level out for some devices (here the keyboard, and a mouse with another key name).
    private let profilerWithoutSomeLevels = """
    {"SPBluetoothDataType":[{"controller_properties":{"controller_state":"attrib_on"},
      "device_connected":[
        {"Magic Keyboard":{"device_address":"xx:xx:xx:xx:xx:xx","device_minorType":"Keyboard"}},
        {"Mo\\u2019s Mouse":{"device_minorType":"Mouse","device_batteryLevel":"64%"}},
        {"Studio Speaker":{"device_minorType":"Speaker"}}],
      "device_not_connected":[{"Old Trackpad":{"device_minorType":"Trackpad"}}]}]}
    """

    private let registryBatteries = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <array>
      <dict><key>Product</key><string>Magic Keyboard</string><key>BatteryPercent</key><integer>77</integer>
            <key>DeviceAddress</key><string>xx-xx-xx-xx-xx-xx</string><key>SerialNumber</key><string>SECRET</string></dict>
      <dict><key>Product</key><string>Magic Keyboard</string><key>BatteryPercent</key><integer>77</integer></dict>
      <dict><key>Product</key><string>Mo’s Mouse</string><key>BatteryPercent</key><integer>10</integer></dict>
      <dict><key>Product</key><string>Old Trackpad</string><key>BatteryPercent</key><integer>50</integer></dict>
      <dict><key>Product</key><string>Broken</string><key>BatteryPercent</key><integer>400</integer></dict>
    </array>
    </plist>
    """

    func testOtherBatteryKeysAndRegistryLevelsFillTheGaps() throws {
        let report = try XCTUnwrap(BluetoothParser.parse(profilerWithoutSomeLevels))
        XCTAssertEqual(report.connected.map(\.batteryMain), [nil, 64, nil])
        let levels = IORegBatteryParser.parse(registryBatteries)
        XCTAssertEqual(levels, ["Magic Keyboard": 77, "Mo’s Mouse": 10, "Old Trackpad": 50])
        let filled = report.addingBatteries(levels)
        XCTAssertEqual(filled.connected.map(\.batteryLabel), ["77%", "64%", nil], "system_profiler's own level is kept")
        XCTAssertFalse(filled.paired[0].hasBattery, "Devices that are not connected are left alone")
        XCTAssertEqual(IORegBatteryParser.parse("not a plist"), [:])
    }

    func testReaderAsksTheRegistryOnlyWhenALevelIsMissing() async throws {
        let runner = ScriptedRunner(["SPBluetoothDataType": ok(profilerWithoutSomeLevels), "-r": ok(registryBatteries)])
        let report = try await SystemBluetoothReader(runner: runner).bluetooth()
        XCTAssertEqual(report.connected.first?.batteryMain, 77)
        XCTAssertEqual(runner.calls.map { $0.0 }, ["/usr/sbin/system_profiler", "/usr/sbin/ioreg"])
        XCTAssertEqual(runner.calls.last?.1, ["-r", "-a", "-k", "BatteryPercent"])
        let json = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)
        XCTAssertFalse(json.contains("SECRET") || json.contains("xx-xx"))

        // A registry that cannot be read leaves the report as system_profiler gave it.
        let failing = ScriptedRunner(["SPBluetoothDataType": ok(profilerWithoutSomeLevels), "-r": failed("no")])
        let unfilled = try await SystemBluetoothReader(runner: failing).bluetooth()
        XCTAssertNil(unfilled.connected.first?.batteryMain)
    }

    func testReader() async throws {
        let runner = ScriptedRunner(["SPBluetoothDataType": ok(try fixture("bluetooth"))])
        let report = try await SystemBluetoothReader(runner: runner).bluetooth()
        XCTAssertEqual(report.devices.count, 3)
        XCTAssertEqual(runner.calls.first?.1, ["SPBluetoothDataType", "-json"])
        XCTAssertEqual(runner.calls.count, 1, "Every connected device had a level: the registry is not asked")
    }
}
