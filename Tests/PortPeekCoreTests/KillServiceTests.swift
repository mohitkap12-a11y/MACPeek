import XCTest
@testable import PortPeekCore

final class KillServiceTests: XCTestCase {
    private func service(_ discovery: ScriptedDiscovery, _ inspector: FakeInspector, grace: TimeInterval = 0.3) -> KillService {
        KillService(discovery: discovery, inspector: inspector, gracePeriod: grace, forceTimeout: 0.3, pollInterval: 0.02, ownPID: 1)
    }

    func testGracefulTerminationSendsSIGTERMOnlyAndVerifiesRelease() async {
        let target = port(3000, pid: 100, start: 50)
        // scan 1: validation sees the port; scan 2+: port is gone.
        let discovery = ScriptedDiscovery([[target], []])
        let inspector = FakeInspector(alive: [100], starts: [100: 50])
        let result = await service(discovery, inspector).terminate(target)
        XCTAssertEqual(result, .terminated)
        XCTAssertEqual(inspector.signals.get().map(\.1), [SIGTERM])
    }

    func testProcessAlreadyExited() async {
        let target = port(3000, pid: 100)
        let inspector = FakeInspector(alive: [])
        let result = await service(ScriptedDiscovery([[]]), inspector).terminate(target)
        XCTAssertEqual(result, .alreadyExited)
        XCTAssertTrue(inspector.signals.get().isEmpty)
    }

    func testPortAlreadyReleasedButProcessAlive() async {
        let target = port(3000, pid: 100)
        let inspector = FakeInspector(alive: [100])
        let result = await service(ScriptedDiscovery([[]]), inspector).terminate(target)
        XCTAssertEqual(result, .portAlreadyReleased)
        XCTAssertTrue(inspector.signals.get().isEmpty, "must not kill a process that no longer owns the port")
    }

    func testTargetChangedWhenAnotherProcessOwnsPort() async {
        let target = port(3000, pid: 100)
        let inspector = FakeInspector(alive: [100, 200])
        let result = await service(ScriptedDiscovery([[port(3000, pid: 200)]]), inspector).terminate(target)
        XCTAssertEqual(result, .targetChanged)
        XCTAssertTrue(inspector.signals.get().isEmpty)
    }

    func testPIDReuseDetectedByStartTime() async {
        let target = port(3000, pid: 100, start: 1000)
        // Same pid, same name, same port — but the process started at a different time.
        let inspector = FakeInspector(alive: [100], starts: [100: 5000])
        let result = await service(ScriptedDiscovery([[port(3000, pid: 100)]]), inspector).terminate(target)
        XCTAssertEqual(result, .targetChanged)
        XCTAssertTrue(inspector.signals.get().isEmpty)
    }

    func testNameMismatchIsTargetChanged() async {
        let target = port(3000, pid: 100, name: "node")
        let inspector = FakeInspector(alive: [100])
        let result = await service(ScriptedDiscovery([[port(3000, pid: 100, name: "python")]]), inspector).terminate(target)
        XCTAssertEqual(result, .targetChanged)
    }

    func testPermissionDenied() async {
        let target = port(3000, pid: 100)
        let inspector = FakeInspector(alive: [100])
        inspector.signalError = EPERM
        let result = await service(ScriptedDiscovery([[target]]), inspector).terminate(target)
        XCTAssertEqual(result, .permissionDenied)
    }

    func testProcessVanishesBetweenValidationAndSignal() async {
        let target = port(3000, pid: 100)
        let inspector = FakeInspector(alive: [100])
        inspector.signalError = ESRCH
        let result = await service(ScriptedDiscovery([[target]]), inspector).terminate(target)
        XCTAssertEqual(result, .alreadyExited)
    }

    func testStillRunningAfterSIGTERMDoesNotEscalateAutomatically() async {
        let target = port(3000, pid: 100)
        let inspector = FakeInspector(alive: [100])
        inspector.diesOnSignal = false
        let result = await service(ScriptedDiscovery([[target]]), inspector).terminate(target)
        XCTAssertEqual(result, .stillRunning)
        XCTAssertEqual(inspector.signals.get().map(\.1), [SIGTERM], "SIGKILL must require an explicit call")
    }

    func testForceTerminateRevalidatesAndSendsSIGKILL() async {
        let target = port(3000, pid: 100)
        let discovery = ScriptedDiscovery([[target], []])
        let inspector = FakeInspector(alive: [100])
        let result = await service(discovery, inspector).forceTerminate(target)
        XCTAssertEqual(result, .terminated)
        XCTAssertEqual(inspector.signals.get().map(\.1), [SIGKILL])
        XCTAssertGreaterThanOrEqual(discovery.calls.get(), 2, "force-kill must rescan before signalling")
    }

    func testForceTerminateRefusesWhenTargetChangedSinceFirstAttempt() async {
        let target = port(3000, pid: 100)
        let inspector = FakeInspector(alive: [100, 300])
        let result = await service(ScriptedDiscovery([[port(3000, pid: 300)]]), inspector).forceTerminate(target)
        XCTAssertEqual(result, .targetChanged)
        XCTAssertTrue(inspector.signals.get().isEmpty)
    }

    func testPortStillHeldAfterExitIsReported() async {
        let target = port(3000, pid: 100)
        let inspector = FakeInspector(alive: [100])
        let result = await service(ScriptedDiscovery([[target]]), inspector).terminate(target)
        guard case .failed = result else { return XCTFail("expected .failed, got \(result)") }
    }

    func testRefusesPID1AndSelf() async {
        let inspector = FakeInspector(alive: [1, 42])
        let svc = KillService(discovery: ScriptedDiscovery([[port(80, pid: 1)]]), inspector: inspector, ownPID: 42)
        for pid in [1, 42] {
            let r = await svc.terminate(port(80, pid: pid))
            guard case .failed = r else { return XCTFail("expected refusal for pid \(pid)") }
        }
        XCTAssertTrue(inspector.signals.get().isEmpty)
    }

    func testScanFailureIsReportedNotSignalled() async {
        let discovery = ScriptedDiscovery([[]])
        discovery.failure = PortDiscoveryError.commandFailed("boom")
        let inspector = FakeInspector(alive: [100])
        let result = await service(discovery, inspector).terminate(port(3000, pid: 100))
        guard case .failed = result else { return XCTFail("expected .failed") }
        XCTAssertTrue(inspector.signals.get().isEmpty)
    }

    func testResultMessagesAndSuccessMapping() {
        let t = port(3000, pid: 100)
        XCTAssertTrue(TerminationResult.terminated.isSuccess)
        XCTAssertTrue(TerminationResult.alreadyExited.isSuccess)
        XCTAssertTrue(TerminationResult.portAlreadyReleased.isSuccess)
        XCTAssertFalse(TerminationResult.permissionDenied.isSuccess)
        XCTAssertFalse(TerminationResult.targetChanged.isSuccess)
        XCTAssertTrue(TerminationResult.terminated.message(for: t).contains("Port 3000 freed"))
        XCTAssertTrue(TerminationResult.permissionDenied.message(for: t).contains("Permission denied"))
    }
}
