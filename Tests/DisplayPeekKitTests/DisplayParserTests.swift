import XCTest
@testable import DisplayPeekKit
import MacPeekCore

final class DisplayParserTests: XCTestCase {
    func testRealMacMiniWithOneUltrawideDisplay() throws {
        let report = try DisplayParser.parse(try fixture("mac_mini_one_display"))
        XCTAssertEqual(report.gpus, [GPUInfo(name: "Apple M2", cores: 10)])
        let display = try XCTUnwrap(report.displays.first)
        XCTAssertEqual(report.displays.count, 1)
        XCTAssertEqual(display.name, "LG HDR WQHD")
        XCTAssertEqual(display.gpuName, "Apple M2")
        XCTAssertEqual(display.nativeResolution, "3440 × 1440")
        XCTAssertEqual(display.uiResolution, "3440 × 1440")
        XCTAssertEqual(display.refreshLabel, "100 Hz")
        XCTAssertEqual(display.scaling, .native)
        XCTAssertEqual(display.isMain, true)
        XCTAssertEqual(display.isMirrored, false)
        XCTAssertEqual(display.isOnline, true)
        XCTAssertEqual(display.vendorID, "0x1e6d")
        XCTAssertEqual(display.productID, "0x7756")
        XCTAssertEqual(display.manufactured, "2023, week 2")
        // macOS says rotation is *supported*, not that the display is rotated: shown as reported.
        XCTAssertTrue(display.details.contains(DisplayDetail(label: "Rotation", value: "Supported")))
    }

    func testSerialNumbersNeverAppear() throws {
        let report = try DisplayParser.parse(try fixture("mac_mini_one_display"))
        let text = try XCTUnwrap(report.displays.first).copyText.lowercased()
        XCTAssertFalse(text.contains("serial"))
        XCTAssertFalse(text.contains("31d4a"))

        let json = """
        {"SPDisplaysDataType":[{"_name":"GPU","spdisplays_ndrvs":[{"_name":"D","spdisplays_serial":"ABC123","_spdisplays_display-serial-number":"XYZ"}]}]}
        """
        let display = try XCTUnwrap(DisplayParser.parse(json).displays.first)
        XCTAssertTrue(display.details.isEmpty)
        XCTAssertFalse(display.copyText.contains("ABC123"))
    }

    func testRetinaScalingAndFractionalRefresh() throws {
        let json = """
        {"SPDisplaysDataType":[{"_name":"Apple M3","sppci_model":"Apple M3","spdisplays_ndrvs":[
          {"_name":"Built-in","_spdisplays_pixels":"3024 x 1964","_spdisplays_resolution":"1512 x 982 @ 120.00Hz","spdisplays_main":"spdisplays_yes"},
          {"_name":"TV","_spdisplays_pixels":"3840 x 2160","_spdisplays_resolution":"2560 x 1440 @ 59.94Hz"}]}]}
        """
        let displays = try DisplayParser.parse(json).displays
        XCTAssertEqual(displays[0].scaling.label, "HiDPI (2×)")
        XCTAssertEqual(displays[0].refreshLabel, "120 Hz")
        XCTAssertEqual(displays[1].scaling.label, "Scaled (1.5×)")
        XCTAssertEqual(displays[1].refreshLabel, "59.94 Hz")
        XCTAssertNil(displays[1].isMain, "an absent flag stays unknown rather than becoming 'No'")
    }

    func testSameWidthButDifferentHeightIsNotCalledNative() throws {
        let json = """
        {"SPDisplaysDataType":[{"spdisplays_ndrvs":[
          {"_name":"Odd","_spdisplays_pixels":"1920 x 1200","_spdisplays_resolution":"1920 x 1080 @ 60.00Hz"}]}]}
        """
        let display = try XCTUnwrap(DisplayParser.parse(json).displays.first)
        XCTAssertEqual(display.scaling, .differentShape)
        XCTAssertNotEqual(display.scaling.label, "Native (1×)")
    }

    func testMissingFieldsStayNil() throws {
        let display = try XCTUnwrap(DisplayParser.parse(#"{"SPDisplaysDataType":[{"spdisplays_ndrvs":[{}]}]}"#).displays.first)
        XCTAssertEqual(display.name, "Display")
        XCTAssertNil(display.nativeResolution)
        XCTAssertNil(display.refreshLabel)
        XCTAssertEqual(display.scaling, .unknown)
    }

    func testAdapterWithoutDisplaysYieldsNoDisplays() throws {
        let report = try DisplayParser.parse(#"{"SPDisplaysDataType":[{"_name":"Apple M1"}]}"#)
        XCTAssertEqual(report.gpus.count, 1)
        XCTAssertTrue(report.displays.isEmpty)
    }

    func testBadInputThrows() {
        XCTAssertThrowsError(try DisplayParser.parse("not json")) { XCTAssertEqual($0 as? DisplayParseError, .notJSON) }
        XCTAssertThrowsError(try DisplayParser.parse(#"{"other":[]}"#)) { XCTAssertEqual($0 as? DisplayParseError, .unexpectedShape) }
    }

    func testDiscoveryRunsSystemProfilerAndParses() async throws {
        let runner = ScriptedRunner(["SPDisplaysDataType": ok(try fixture("mac_mini_one_display"))])
        let report = try await SystemProfilerDisplayDiscovery(runner: runner).report()
        XCTAssertEqual(report.displays.count, 1)
        XCTAssertEqual(runner.calls.first?.0, "/usr/sbin/system_profiler")
        XCTAssertEqual(runner.calls.first?.1, ["SPDisplaysDataType", "-json"])
    }

    func testDiscoveryFailureCarriesStderr() async {
        let runner = ScriptedRunner(["SPDisplaysDataType": failed("boom")])
        do {
            _ = try await SystemProfilerDisplayDiscovery(runner: runner).report()
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? DisplayError, .commandFailed("boom"))
        }
    }
}
