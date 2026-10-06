import XCTest
@testable import USBPeekKit
import MacPeekCore

final class USBParserTests: XCTestCase {
    private func parsed() throws -> [USBBus] { IORegUSBParser.parse(try fixture("mac_mini_ioreg_usb")) }

    func testRealMacMiniControllersAndDeviceTree() throws {
        let buses = try parsed()
        XCTAssertEqual(buses.count, 3)
        XCTAssertEqual(buses.map(\.busNumber), [0, 1, 2])
        XCTAssertEqual(buses.map(\.deviceCount), [0, 1, 3])
        XCTAssertEqual(buses[1].devices.map(\.name), ["USB2.1 Hub"])
        let bus = buses[2]
        XCTAssertEqual(bus.title, "USB bus 2")
        XCTAssertEqual(bus.controllerClass, "AppleEmbeddedUSBXHCIASMedia3142")
        // Two hubs at the top; the mouse hangs off the USB 2 hub.
        XCTAssertEqual(bus.devices.map(\.name), ["USB3.1 Hub", "USB2.1 Hub"])
        XCTAssertEqual(bus.devices[1].children.map(\.name), ["USB OPTICAL MOUSE"])
        XCTAssertTrue(bus.devices[0].children.isEmpty)
    }

    func testDeviceDetailsComeFromTheRegistry() throws {
        let hub3 = try XCTUnwrap(parsed()[2].devices.first)
        XCTAssertEqual(hub3.vendorName, "GenesysLogic")
        XCTAssertEqual(hub3.vendorProductLabel, "0x05E3:0x0626")
        XCTAssertEqual(hub3.speedLabel, "5 Gb/s")
        XCTAssertEqual(hub3.declaredUSBVersion, "3.20")
        XCTAssertTrue(hub3.isHub)
        XCTAssertEqual(hub3.deviceClassLabel, "Hub")

        let hub2 = try parsed()[2].devices[1]
        XCTAssertEqual(hub2.speedLabel, "480 Mb/s")
        XCTAssertEqual(hub2.declaredUSBVersion, "2.10")

        let mouse = try XCTUnwrap(hub2.children.first)
        XCTAssertEqual(mouse.speedLabel, "1.5 Mb/s")
        XCTAssertEqual(mouse.declaredUSBVersion, "1.10")
        XCTAssertNil(mouse.vendorName, "the mouse reports no vendor name; none is invented")
        XCTAssertEqual(mouse.deviceClassLabel, "Defined per interface")
        XCTAssertFalse(mouse.isHub)
    }

    func testSerialNumbersNeverEnterTheModel() throws {
        let snapshot = USBSnapshot(buses: try parsed(), thunderboltPorts: [])
        for device in snapshot.allDevices {
            XCTAssertFalse(device.copyText.lowercased().contains("serial"))
            XCTAssertFalse(device.copyText.contains("redacted"))
        }
        // Even a serial that is present in the raw text can't leak: the line is dropped by key.
        let text = """
        +-o Root  <class IORegistryEntry, id 0x1, retain 1>
          +-o XHCI@01000000  <class AppleXHCI, id 0x2, registered>
            +-o Disk@01100000  <class IOUSBHostDevice, id 0x3, registered>
              {
                "USB Product Name" = "Disk"
                "USB Serial Number" = "SECRET123"
                "kUSBSerialNumberString" = "SECRET123"
                "iSerialNumber" = 3
              }
        """
        let devices = IORegUSBParser.parse(text).flatMap(\.devices)
        XCTAssertEqual(devices.map(\.name), ["Disk"])
        XCTAssertFalse(devices[0].copyText.contains("SECRET123"))
    }

    func testNonDeviceEntriesArePassedThrough() {
        let text = """
        +-o Root  <class IORegistryEntry, id 0x1, retain 1>
          +-o XHCI@01000000  <class AppleXHCI, id 0x2, registered>
            +-o Wrapper@01100000  <class IOSomethingElse, id 0x3, registered>
              +-o Phone@01110000  <class IOUSBHostDevice, id 0x4, registered>
                {
                  "USB Product Name" = "Phone"
                  "idVendor" = 1452
                  "idProduct" = 4776
                }
        """
        let bus = IORegUSBParser.parse(text)[0]
        XCTAssertEqual(bus.devices.map(\.name), ["Phone"])
        XCTAssertEqual(bus.devices[0].vendorProductLabel, "0x05AC:0x12A8")
    }

    func testSpeedAndVersionFormatting() {
        XCTAssertEqual(USBSpeed.label(480_000_000), "480 Mb/s")
        XCTAssertEqual(USBSpeed.label(5_000_000_000), "5 Gb/s")
        XCTAssertEqual(USBSpeed.label(10_000_000_000), "10 Gb/s")
        XCTAssertEqual(USBSpeed.label(12_000_000), "12 Mb/s")
        XCTAssertEqual(USBSpeed.label(1_500_000), "1.5 Mb/s")
        XCTAssertEqual(IORegUSBParser.versionLabel(0x0310), "3.10")
        XCTAssertEqual(IORegUSBParser.versionLabel(0x0200), "2.00")
    }

    func testEmptyOrGarbageInputIsNoBuses() {
        XCTAssertTrue(IORegUSBParser.parse("").isEmpty)
        XCTAssertTrue(IORegUSBParser.parse("nonsense\nmore nonsense").isEmpty)
    }
}

final class ThunderboltAndDiscoveryTests: XCTestCase {
    func testRealMacMiniHasTwoIdlePorts() throws {
        let ports = try XCTUnwrap(ThunderboltParser.parse(try fixture("mac_mini_thunderbolt")))
        XCTAssertEqual(ports.count, 2)
        XCTAssertTrue(ports.allSatisfy { !$0.isConnected })
        XCTAssertEqual(ports.map(\.status), ["No device connected", "No device connected"])
        XCTAssertEqual(ports.map(\.speed), ["Up to 40 Gb/s", "Up to 40 Gb/s"])
        XCTAssertEqual(Set(ports.compactMap(\.receptacle)), ["1", "2"])
        XCTAssertEqual(Set(ports.map(\.busName)), ["Thunderbolt / USB4 bus 0", "Thunderbolt / USB4 bus 1"])
    }

    func testConnectedPortListsDeviceNames() throws {
        let json = """
        {"SPThunderboltDataType":[{"_name":"thunderboltusb4_bus_0","receptacle_1_tag":{"receptacle_id_key":"1","receptacle_status_key":"receptacle_connected","current_speed_key":"Up to 40 Gb/s"},
          "_items":[{"_name":"dock","device_name_key":"CalDigit TS4","_items":[{"_name":"x","device_name_key":"Studio Display"}]}]}]}
        """
        let port = try XCTUnwrap(ThunderboltParser.parse(json)?.first)
        XCTAssertTrue(port.isConnected)
        XCTAssertEqual(port.status, "Connected")
        XCTAssertEqual(port.connectedDevices, ["CalDigit TS4", "Studio Display"])
    }

    func testUnreadableThunderboltIsNil() {
        XCTAssertNil(ThunderboltParser.parse("no thunderbolt hardware"))
        XCTAssertNil(ThunderboltParser.parse(#"{"other":1}"#))
    }

    func testDiscoveryCombinesUSBAndThunderbolt() async throws {
        let runner = ScriptedRunner([
            "-p": ok(try fixture("mac_mini_ioreg_usb")),
            "SPThunderboltDataType": ok(try fixture("mac_mini_thunderbolt")),
        ])
        let snapshot = try await SystemUSBDiscovery(runner: runner).snapshot()
        XCTAssertEqual(snapshot.deviceCount, 4)
        XCTAssertEqual(snapshot.thunderboltPorts.count, 2)
        XCTAssertNil(snapshot.thunderboltNote)
        XCTAssertEqual(runner.calls[0].0, "/usr/sbin/ioreg")
        XCTAssertEqual(runner.calls[0].1, ["-p", "IOUSB", "-l", "-w0"])
        XCTAssertEqual(runner.calls[1].1, ["SPThunderboltDataType", "-json"])
    }

    func testThunderboltFailureDoesNotHideUSB() async throws {
        let runner = ScriptedRunner([
            "-p": ok(try fixture("mac_mini_ioreg_usb")),
            "SPThunderboltDataType": failed("no thunderbolt"),
        ])
        let snapshot = try await SystemUSBDiscovery(runner: runner).snapshot()
        XCTAssertEqual(snapshot.deviceCount, 4)
        XCTAssertTrue(snapshot.thunderboltPorts.isEmpty)
        XCTAssertNotNil(snapshot.thunderboltNote)
    }

    func testIoregFailureIsAnError() async {
        let runner = ScriptedRunner(["-p": failed("ioreg broke")])
        do {
            _ = try await SystemUSBDiscovery(runner: runner).snapshot()
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? USBError, .commandFailed("ioreg broke"))
        }
    }

    func testCancellationPropagates() async {
        let runner = ScriptedRunner([
            "-p": ok(""),
            "SPThunderboltDataType": .failure(CommandError.cancelled),
        ])
        do {
            _ = try await SystemUSBDiscovery(runner: runner).snapshot()
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? CommandError, .cancelled)
        }
    }
}
