import XCTest
@testable import SleepPeekKit
import MacPeekCore

final class AssertionParserTests: XCTestCase {
    private func report() throws -> AssertionReport { AssertionParser.parse(try fixture("assertions")) }

    func testSystemWideStatus() throws {
        let r = try report()
        XCTAssertEqual(r.systemStatus.count, 10)
        XCTAssertEqual(r.count("PreventUserIdleSystemSleep"), 1)
        XCTAssertEqual(r.count("UserIsActive"), 1)
        XCTAssertEqual(r.count("PreventSystemSleep"), 0)
        XCTAssertEqual(r.count("PreventSystemSleepSecurityIndicator"), 0)
        XCTAssertEqual(r.count("DoesNotExist"), 0)
    }

    func testProcessAssertionsFromARealMac() throws {
        let a = try report().assertions
        XCTAssertEqual(a.map(\.processName), ["bluetoothd", "sharingd", "powerd", "WindowServer"])
        XCTAssertEqual(a[0].pid, 4647)
        XCTAssertEqual(a[0].type, "PreventUserIdleSystemSleep")
        XCTAssertEqual(a[0].name, "com.apple.BTStack")
        XCTAssertEqual(a[0].heldFor, "00:01:49")
        XCTAssertEqual(a[2].name, "Powerd - Prevent sleep while display is on")
        XCTAssertEqual(a[2].heldFor, "01:01:14")
        XCTAssertTrue(a[0].preventsSystemSleep)
        XCTAssertFalse(a[3].blocksSleep, "UserIsActive is not a sleep blocker")
        XCTAssertTrue(a[3].name.contains("MX Master 3S"))
        // The timeout line printed under WindowServer's assertion is kept as a detail.
        XCTAssertEqual(a[3].details, ["Timeout will fire in 600 secs Action=TimeoutActionRelease"])
    }

    func testKernelAssertions() throws {
        let k = try report().kernelAssertions
        XCTAssertEqual(k.map(\.id), [537, 539, 6947, 19645, 21319])
        XCTAssertEqual(k[0].description, "com.apple.usb.externaldevice.02100000")
        XCTAssertEqual(k[0].owner, "USB3.1 Hub")
        XCTAssertEqual(k[2].owner, "IOSkywalkNetworkBSDClient")
        XCTAssertEqual(k[4].owner, "USB OPTICAL MOUSE")
    }

    func testEmptyAndGarbage() {
        let empty = AssertionParser.parse("")
        XCTAssertTrue(empty.assertions.isEmpty)
        XCTAssertTrue(empty.systemStatus.isEmpty)
        XCTAssertTrue(AssertionParser.parse("hello\nworld").assertions.isEmpty)
    }

    func testProcessNamesWithParenthesesAndSpaces() {
        let text = """
        Listed by owning process:
           pid 12(Google Chrome Helper (Renderer)): [0x0001] 00:00:05 NoDisplaySleepAssertion named: "Video "playing""
        """
        let a = AssertionParser.parse(text).assertions
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(a[0].processName, "Google Chrome Helper (Renderer)")
        XCTAssertEqual(a[0].name, "Video \"playing\"")
        XCTAssertTrue(a[0].preventsDisplaySleep)
    }
}

final class PowerSettingsParserTests: XCTestCase {
    func testRealPmsetOutput() throws {
        let s = PowerSettingsParser.parse(try fixture("pmset_g"))
        XCTAssertEqual(s.sleepMinutes, 1)
        XCTAssertEqual(s.displaySleepMinutes, 10)
        XCTAssertEqual(s.values["Sleep On Power Button"], 1)
        XCTAssertEqual(s.values["womp"], 1)
        XCTAssertEqual(s.values["standby"], 0)
        XCTAssertEqual(s.preventedBy["sleep"], ["useractivityd", "bluetoothd", "sharingd", "powerd"])
        XCTAssertNil(s.preventedBy["displaysleep"])
    }
}

final class SleepLogParserTests: XCTestCase {
    private func history(limit: Int = 100) throws -> SleepHistory { SleepLogParser.parse(try fixture("sleep_log"), limit: limit) }

    func testOnlySleepWakeAndDarkWakeEventsAreKept() throws {
        let h = try history()
        XCTAssertFalse(h.events.isEmpty)
        XCTAssertTrue(h.events.allSatisfy { [.sleep, .wake, .darkWake].contains($0.kind) })
        XCTAssertEqual(h.count(of: .wake), 0)
        XCTAssertGreaterThan(h.count(of: .darkWake), 0)
        XCTAssertGreaterThan(h.count(of: .sleep), 0)
    }

    func testNewestFirstAndLimited() throws {
        let h = try history(limit: 5)
        XCTAssertEqual(h.events.count, 5)
        XCTAssertEqual(h.events, h.events.sorted { $0.date > $1.date })
    }

    func testReasonsArePreservedVerbatim() throws {
        let h = try history()
        let dark = try XCTUnwrap(h.events.first { $0.kind == .darkWake })
        XCTAssertEqual(dark.reason, "smc.sysState.Wake(0x70070000) usb3 SMC.OutboxNotEmpty pcie-xhci/")
        XCTAssertEqual(dark.powerSource, "AC")
        let sleep = try XCTUnwrap(h.events.first { $0.kind == .sleep })
        XCTAssertEqual(sleep.reason, "'Maintenance Sleep':TCPKeepAlive=active")
        XCTAssertEqual(sleep.powerSource, "AC")
    }

    func testTimestampsHonourTheLoggedOffset() throws {
        // 2026-10-06 18:24:57 +0530 == 12:54:57 UTC.
        let h = try history(limit: 1000)
        let first = try XCTUnwrap(h.events.last)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: first.date)
        XCTAssertEqual([parts.year, parts.month, parts.day, parts.hour, parts.minute, parts.second], [2026, 10, 6, 12, 54, 57])
    }

    func testLatestWakeRequestsAreParsed() throws {
        let h = try history()
        XCTAssertFalse(h.wakeRequests.isEmpty)
        let mdns = try XCTUnwrap(h.wakeRequests.first { $0.process == "mDNSResponder" })
        XCTAssertEqual(mdns.request, "Maintenance")
        XCTAssertEqual(mdns.info, "DHCP lease renewal")
        XCTAssertNotNil(mdns.wakeAt)
        XCTAssertNotNil(h.wakeRequestsRecordedAt)
    }

    func testWakeRequestWithoutInfoDoesNotSwallowTheNextEntry() {
        let text = """
        2026-01-02 03:00:00 +0000 Wake Requests       \t[process=powerd request=CSPNEvaluation deltaSecs=3905 wakeAt=2026-01-02 04:05:05] [process=powerd request=UserWake deltaSecs=100 wakeAt=2026-01-02 03:01:40 info="alarm"]
        """
        let requests = SleepLogParser.parse(text).wakeRequests
        XCTAssertEqual(requests.map(\.request), ["CSPNEvaluation", "UserWake"])
        XCTAssertEqual(requests.map(\.info), ["", "alarm"])
        XCTAssertTrue(requests.allSatisfy { $0.wakeAt != nil })
    }

    func testBatteryAndNoReason() {
        let text = """
        2026-01-02 03:04:05 +0000 Wake                \tWake from Normal Sleep [CDNVA] : due to EC.LidOpen/Lid Open Using BATT (Charge:55%) 3600 secs
        2026-01-02 04:00:00 +0000 Sleep               \tEntering Sleep state
        """
        let events = SleepLogParser.parse(text).events
        let wake = events.first { $0.kind == .wake }
        XCTAssertEqual(wake?.reason, "EC.LidOpen/Lid Open")
        XCTAssertEqual(wake?.powerSource, "Batt")
        XCTAssertNil(events.first { $0.kind == .sleep }?.reason)
    }

    func testEmptyLog() {
        let h = SleepLogParser.parse("")
        XCTAssertTrue(h.events.isEmpty)
        XCTAssertTrue(h.wakeRequests.isEmpty)
        XCTAssertNil(h.wakeRequestsRecordedAt)
    }
}

final class SleepAnalysisTests: XCTestCase {
    func testRealMacIsHeldAwakeAndSeparatesFactFromInference() throws {
        let report = AssertionParser.parse(try fixture("assertions"))
        let settings = PowerSettingsParser.parse(try fixture("pmset_g"))
        let d = SleepAnalysis.diagnose(report: report, settings: settings)
        XCTAssertTrue(d.systemSleepBlocked)
        XCTAssertFalse(d.displaySleepBlocked)
        XCTAssertTrue(d.userActive)
        XCTAssertEqual(d.headline, "Something is keeping your Mac awake")
        // powerd's "Prevent sleep while display is on" is the system's own hold, not a blocker to chase.
        XCTAssertEqual(d.blockers.map(\.assertion.processName), ["bluetoothd", "sharingd"])
        XCTAssertEqual(d.expectedHolds.map(\.assertion.processName), ["powerd"])
        XCTAssertEqual(d.macOSReportedBlockers, ["useractivityd", "bluetoothd", "sharingd", "powerd"])

        let powerd = try XCTUnwrap(d.expectedHolds.first)
        XCTAssertEqual(powerd.findings.first?.basis, .verified)
        XCTAssertTrue(powerd.findings.contains { $0.basis == .inference && $0.text.contains("display is on") })
        // A blocker we know nothing about gets facts only, never a guess.
        let sharingd = try XCTUnwrap(d.blockers.first { $0.assertion.processName == "sharingd" })
        XCTAssertTrue(sharingd.findings.allSatisfy { $0.basis == .verified })
    }

    func testOnlyTheDisplayBeingOnIsNotReportedAsABlocker() {
        let report = AssertionParser.parse("""
        Assertion status system-wide:
           PreventUserIdleSystemSleep     1
           UserIsActive                   0
        Listed by owning process:
           pid 4598(powerd): [0x1] 01:01:14 PreventUserIdleSystemSleep named: "Powerd - Prevent sleep while display is on"
        """)
        let d = SleepAnalysis.diagnose(report: report, settings: nil)
        XCTAssertFalse(d.systemSleepBlocked)
        XCTAssertTrue(d.blockers.isEmpty)
        XCTAssertEqual(d.expectedHolds.count, 1)
        XCTAssertEqual(d.headline, "Your Mac stays awake while the display is on")
    }

    func testNothingBlocking() {
        let report = AssertionParser.parse("""
        Assertion status system-wide:
           PreventUserIdleSystemSleep     0
           UserIsActive                   0
        Listed by owning process:
        """)
        let d = SleepAnalysis.diagnose(report: report, settings: nil)
        XCTAssertFalse(d.systemSleepBlocked)
        XCTAssertFalse(d.userActive)
        XCTAssertTrue(d.blockers.isEmpty)
        XCTAssertEqual(d.headline, "Nothing is blocking sleep right now")
    }

    func testDisplayOnlyBlock() {
        let report = AssertionParser.parse("""
        Assertion status system-wide:
           PreventUserIdleDisplaySleep    1
        Listed by owning process:
           pid 9(Zoom): [0x1] 00:10:00 PreventUserIdleDisplaySleep named: "Zoom meeting"
        """)
        let d = SleepAnalysis.diagnose(report: report, settings: nil)
        XCTAssertFalse(d.systemSleepBlocked)
        XCTAssertTrue(d.displaySleepBlocked)
        XCTAssertEqual(d.headline, "Something is keeping the display awake")
    }
}

final class SleepServiceTests: XCTestCase {
    func testSnapshotRunsReadOnlyPmsetCommands() async throws {
        // `pmset -g assertions` and `pmset -g` share the first argument, so route by the full arguments.
        let routed = RoutedRunner(assertions: try fixture("assertions"), settings: try fixture("pmset_g"), log: try fixture("sleep_log"))
        let snapshot = try await PMSetSleepReader(runner: routed, historyRunner: routed).snapshot()
        XCTAssertTrue(snapshot.diagnosis.systemSleepBlocked)
        XCTAssertEqual(snapshot.settings?.sleepMinutes, 1)
        XCTAssertEqual(routed.calls.map { $0.1 }, [["-g", "assertions"], ["-g"]])
        XCTAssertTrue(routed.calls.allSatisfy { $0.0 == "/usr/bin/pmset" })
    }

    func testSettingsFailureIsNotFatal() async throws {
        let routed = RoutedRunner(assertions: try fixture("assertions"), settings: nil, log: "")
        let snapshot = try await PMSetSleepReader(runner: routed, historyRunner: routed).snapshot()
        XCTAssertNil(snapshot.settings)
        XCTAssertTrue(snapshot.diagnosis.systemSleepBlocked)
    }

    func testAssertionsFailureIsAnError() async {
        let routed = RoutedRunner(assertions: nil, settings: "", log: "")
        do {
            _ = try await PMSetSleepReader(runner: routed, historyRunner: routed).snapshot()
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? SleepError, .commandFailed("pmset failed"))
        }
    }

    func testHistoryUsesTheLogCommand() async throws {
        let routed = RoutedRunner(assertions: "", settings: "", log: try fixture("sleep_log"))
        let history = try await PMSetSleepReader(runner: routed, historyRunner: routed).history(limit: 10)
        XCTAssertEqual(history.events.count, 10)
        XCTAssertEqual(routed.calls.first?.1, ["-g", "log"])
    }
}

/// Routes by the exact pmset arguments; `nil` for a section means that command fails.
final class RoutedRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [(String, [String])] = []
    private let assertions: String?
    private let settings: String?
    private let log: String?
    init(assertions: String?, settings: String?, log: String?) {
        self.assertions = assertions
        self.settings = settings
        self.log = log
    }
    var calls: [(String, [String])] { lock.lock(); defer { lock.unlock() }; return _calls }
    private func record(_ executable: String, _ arguments: [String]) {
        lock.lock(); defer { lock.unlock() }
        _calls.append((executable, arguments))
    }
    func run(_ executable: String, _ arguments: [String]) async throws -> CommandOutput {
        record(executable, arguments)
        let text: String?
        switch arguments {
        case ["-g", "assertions"]: text = assertions
        case ["-g"]: text = settings
        case ["-g", "log"]: text = log
        default: text = nil
        }
        guard let text else { return CommandOutput(stdout: "", stderr: "pmset failed", status: 1) }
        return CommandOutput(stdout: text, stderr: "", status: 0)
    }
}
