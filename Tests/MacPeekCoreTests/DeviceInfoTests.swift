import XCTest
import MacPeekCore

final class DeviceInfoTests: XCTestCase {
    private let boot = Date(timeIntervalSince1970: 1_761_000_000)

    func testUptimeIsMeasuredFromBootAndNeverNegative() {
        let info = DeviceInfo(computerName: nil, localHostName: nil, modelIdentifier: nil, macOSVersion: "26.1", bootTime: boot)
        XCTAssertEqual(info.uptime(at: boot.addingTimeInterval(533_000)), 533_000)
        XCTAssertEqual(info.uptime(at: boot.addingTimeInterval(-60)), 0)
        XCTAssertNil(DeviceInfo(computerName: nil, localHostName: nil, modelIdentifier: nil, macOSVersion: "26.1", bootTime: nil).uptime())
    }

    func testDisplayNamePrefersTheComputerName() {
        XCTAssertEqual(DeviceInfo(computerName: "Design Studio 01", localHostName: "Design-Studio-01", modelIdentifier: nil,
                                  macOSVersion: "26.1", bootTime: nil).displayName, "Design Studio 01")
        XCTAssertEqual(DeviceInfo(computerName: nil, localHostName: "Design-Studio-01", modelIdentifier: nil,
                                  macOSVersion: "26.1", bootTime: nil).displayName, "Design-Studio-01")
        XCTAssertEqual(DeviceInfo(computerName: nil, localHostName: nil, modelIdentifier: nil, macOSVersion: "26.1", bootTime: nil).displayName,
                       "This Mac")
    }

    func testVersionLabelDropsAZeroPatch() {
        XCTAssertEqual(DeviceInfo.versionLabel(major: 26, minor: 1, patch: 0), "26.1")
        XCTAssertEqual(DeviceInfo.versionLabel(major: 15, minor: 7, patch: 2), "15.7.2")
    }

    func testUptimeLabels() {
        XCTAssertEqual(UptimeText.label(533_000), "6d 4h")
        XCTAssertEqual(UptimeText.label(33_120), "9h 12m")
        XCTAssertEqual(UptimeText.label(720), "12m")
        XCTAssertEqual(UptimeText.label(20), "<1m")
        XCTAssertEqual(UptimeText.label(-5), "<1m")
    }

    func testReaderAlwaysReportsAVersion() {
        let info = SystemDeviceInfoReader().read()
        XCTAssertFalse(info.macOSVersion.isEmpty)
        if let boot = info.bootTime { XCTAssertLessThan(boot, Date()) }
    }

    func testDeviceInfoRoundTrips() throws {
        let info = DeviceInfo(computerName: "Design Studio 01", localHostName: "Design-Studio-01", modelIdentifier: "Mac16,7",
                              macOSVersion: "26.1", bootTime: boot)
        XCTAssertEqual(try JSONDecoder().decode(DeviceInfo.self, from: try JSONEncoder().encode(info)), info)
    }
}
