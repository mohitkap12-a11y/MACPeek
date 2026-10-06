import XCTest
@testable import ProcessPeekKit
import MacPeekCore

final class ProcessTerminatorTests: XCTestCase {
    private func entry(_ pid: Int = 42, name: String = "node", start: TimeInterval? = 100, user: String = "me") -> ProcessEntry {
        ProcessEntry(pid: pid, ppid: 1, uid: 501, user: user, state: "S", startTime: nil, elapsed: "01:00", cpuPercent: 0,
                     residentKB: 1, executable: "/usr/local/bin/\(name)", identityStartTime: start)
    }

    /// `ps -o stat=,comm= -p PID` as the fake OS would print it: alive → the process, gone → exit status 1.
    private func runner(_ inspector: FakeInspector, comm: String = "/usr/local/bin/node", afterExit: String? = nil) -> RoutedRunner {
        RoutedRunner { _ in
            if inspector.alive.get().contains(42) { return output("S   \(comm)\n") }
            if let afterExit { return output(afterExit) }
            return failure("", status: 1)
        }
    }

    private func terminator(_ inspector: FakeInspector, _ runner: CommandRunning, ownPID: Int = 99_999) -> ProcessTerminator {
        ProcessTerminator(runner: runner, inspector: inspector, gracePeriod: 0.3, forceTimeout: 0.3, pollInterval: 0.01, ownPID: ownPID)
    }

    func testGracefulTerminationSendsOnlySIGTERMAndVerifiesTheExit() async {
        let inspector = FakeInspector(alive: [42])
        let result = await terminator(inspector, runner(inspector)).terminate(entry())
        XCTAssertEqual(result, .terminated)
        XCTAssertEqual(inspector.signals.get(), [SIGTERM])
    }

    func testPSIsAskedAboutExactlyThisPIDInTheCLocale() async {
        let inspector = FakeInspector(alive: [42])
        let r = runner(inspector)
        _ = await terminator(inspector, r).terminate(entry())
        XCTAssertEqual(r.calls.first?.0, "/usr/bin/env")
        XCTAssertEqual(r.calls.first?.1, ["LC_ALL=C", "/bin/ps", "-o", "stat=,comm=", "-p", "42"])
    }

    func testAReusedPIDIsNeverSignalled() async {
        // PID 42 is alive, but it started at 999, not 100: it is a different process now.
        let inspector = FakeInspector(alive: [42], starts: [42: 999])
        let result = await terminator(inspector, runner(inspector)).terminate(entry(start: 100))
        XCTAssertEqual(result, .targetChanged)
        XCTAssertTrue(inspector.signals.get().isEmpty)
    }

    func testADifferentNameIsNeverSignalled() async {
        let inspector = FakeInspector(alive: [42])
        let result = await terminator(inspector, runner(inspector, comm: "/bin/other")).terminate(entry())
        XCTAssertEqual(result, .targetChanged)
        XCTAssertTrue(inspector.signals.get().isEmpty)
    }

    func testWithoutAProvableIdentityNothingIsSignalled() async {
        let inspector = FakeInspector(alive: [42])
        let result = await terminator(inspector, runner(inspector)).terminate(entry(start: nil))
        guard case .failed(let reason) = result else { return XCTFail("expected failure, got \(result)") }
        XCTAssertTrue(reason.contains("identity"))
        XCTAssertTrue(inspector.signals.get().isEmpty)
    }

    func testPID1AndMacPeekItselfAreProtected() async {
        let inspector = FakeInspector(alive: [1, 42])
        let t = terminator(inspector, runner(inspector), ownPID: 42)
        for pid in [1, 42] {
            let result = await t.terminate(entry(pid))
            guard case .failed(let reason) = result else { return XCTFail("pid \(pid): expected failure, got \(result)") }
            XCTAssertTrue(reason.contains("protected"))
        }
        XCTAssertTrue(inspector.signals.get().isEmpty)
    }

    func testAnExitedProcessIsReportedAsSuchWithoutSignalling() async {
        let inspector = FakeInspector(alive: [])
        let result = await terminator(inspector, runner(inspector)).terminate(entry())
        XCTAssertEqual(result, .alreadyExited)
        XCTAssertTrue(inspector.signals.get().isEmpty)
    }

    func testPermissionDenied() async {
        let inspector = FakeInspector(alive: [42])
        inspector.signalError = EPERM
        let result = await terminator(inspector, runner(inspector)).terminate(entry())
        XCTAssertEqual(result, .permissionDenied)
    }

    func testAProcessThatIgnoresSIGTERMIsNeverEscalatedAutomaticallyAndForceKillRevalidates() async {
        let inspector = FakeInspector(alive: [42])
        inspector.diesOnSignal = false
        let t = terminator(inspector, runner(inspector))
        let first = await t.terminate(entry())
        XCTAssertEqual(first, .stillRunning)
        XCTAssertEqual(inspector.signals.get(), [SIGTERM], "no automatic SIGKILL")

        inspector.diesOnSignal = true
        let forced = await t.forceTerminate(entry())
        XCTAssertEqual(forced, .terminated)
        XCTAssertEqual(inspector.signals.get(), [SIGTERM, SIGKILL])
    }

    func testForceKillOfAReusedPIDIsRefused() async {
        let inspector = FakeInspector(alive: [42], starts: [42: 555])
        let result = await terminator(inspector, runner(inspector)).forceTerminate(entry(start: 100))
        XCTAssertEqual(result, .targetChanged)
        XCTAssertTrue(inspector.signals.get().isEmpty)
    }

    func testAZombieCountsAsGone() async {
        let inspector = FakeInspector(alive: [42])
        let result = await terminator(inspector, runner(inspector, afterExit: "Z   (node)\n")).terminate(entry())
        XCTAssertEqual(result, .terminated)
    }
}

final class ProcessKillSupportTests: XCTestCase {
    private func entry(name: String = "node", user: String = "me") -> ProcessEntry {
        ProcessEntry(pid: 42, ppid: 1, uid: 501, user: user, state: "S", startTime: nil, elapsed: "01:00", cpuPercent: 0,
                     residentKB: 1, executable: "/usr/local/bin/\(name)", identityStartTime: 100)
    }

    func testMessages() {
        let e = entry()
        XCTAssertEqual(TerminationResult.terminated.message(for: e), "✓ Terminated node (PID 42).")
        XCTAssertEqual(TerminationResult.alreadyExited.message(for: e), "node (PID 42) is no longer running.")
        XCTAssertTrue(TerminationResult.targetChanged.message(for: e).contains("different process"))
        XCTAssertTrue(TerminationResult.targetChanged.message(for: e).contains("Nothing was killed"))
        XCTAssertTrue(TerminationResult.permissionDenied.message(for: e).contains("Permission denied"))
        XCTAssertTrue(TerminationResult.stillRunning.message(for: e).contains("did not exit after SIGTERM"))
        XCTAssertTrue(TerminationResult.failed("boom").message(for: e).contains("boom"))
    }

    func testCapabilityMatchesTheOtherUtilities() {
        let permissions = PermissionService(currentUser: "me", ownPID: 7)
        XCTAssertEqual(permissions.capability(for: entry(user: "me")), .canTerminate)
        XCTAssertEqual(permissions.capability(for: entry(user: "root")), .protected)
        XCTAssertEqual(permissions.capability(for: entry(user: "someoneelse")), .permissionRequired)
    }

    func testSessionProcessesCarryAWarning() {
        XCTAssertNotNil(entry(name: "loginwindow").sessionWarning)
        XCTAssertNotNil(entry(name: "launchd").sessionWarning)
        XCTAssertNil(entry(name: "node").sessionWarning)
    }

    func testTheListerRecordsEachProcessesKernelStartTimeForIdentityChecks() async throws {
        let fixture = try fixture("ps_sample")
        let runner = RoutedRunner { _ in output(fixture) }
        let inspector = FakeInspector(alive: [], starts: [4973: 12_345.5])
        let snapshot = try await PSProcessLister(runner: runner, ports: FakePorts(result: .success([])), inspector: inspector).snapshot()
        XCTAssertEqual(snapshot.entry(pid: 4973)?.identityStartTime, 12_345.5)
        XCTAssertNil(snapshot.entry(pid: 4890)?.identityStartTime, "unknown stays unknown, so Kill refuses it")
    }

    func testTargetCarriesTheIdentity() {
        let target = ProcessTarget(entry: entry())
        XCTAssertEqual(target, ProcessTarget(pid: 42, processName: "node", startTime: 100))
    }
}
