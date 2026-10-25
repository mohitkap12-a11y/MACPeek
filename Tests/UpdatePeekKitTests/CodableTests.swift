import XCTest
import UpdatePeekKit

/// Encodes to JSON and back; the value must survive unchanged so a MacPeek Remote console can read it.
private func assertRoundTrips<T: Codable & Equatable>(_ value: T, file: StaticString = #filePath, line: UInt = #line) throws {
    let data = try JSONEncoder().encode(value)
    XCTAssertEqual(try JSONDecoder().decode(T.self, from: data), value, file: file, line: line)
}

final class CodableTests: XCTestCase {
    func testUpdateValuesRoundTrip() throws {
        let checked = Date(timeIntervalSince1970: 1_761_390_724)
        let packages = PackageReport(packages: [OutdatedPackage(name: "node", kind: .formula, installedVersions: ["22.10.0"],
                                                                currentVersion: "22.11.0")], checkedAt: checked)
        try assertRoundTrips([PackageCheckState.notInstalled, .notChecked, .checking, .checked(packages),
                              .failed(message: "brew not found", retryable: false)])
        let report = MacOSUpdateReport(updates: [MacOSUpdate(name: "macOS Tahoe 26.1", version: "26.1", isRecommended: true,
                                                             requiresRestart: true)], source: .softwareUpdateTool, checkedAt: checked)
        try assertRoundTrips([MacOSUpdateState.notChecked, .checking, .known(report), .failed(message: "offline")])
        try assertRoundTrips(OperatingSystemInfo(major: 26, minor: 1, patch: 0, build: "25B78"))
    }
}
