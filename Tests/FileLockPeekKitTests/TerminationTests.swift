import XCTest
@testable import FileLockPeekKit
@testable import MacPeekCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

final class FileLockTerminationTests: XCTestCase {
    private let path = "/Users/me/data.db"

    private func terminator(_ d: ScriptedFileDiscovery, _ i: FakeInspector) -> FileLockTerminator {
        FileLockTerminator(discovery: d, inspector: i, gracePeriod: 0.3, forceTimeout: 0.3, pollInterval: 0.02, ownPID: 1)
    }

    func testGracefulTerminationReleasesTheFile() async {
        let h = holder(100)
        // scan 1 (validation): held. scan 2+ (verification): nobody holds it.
        let inspector = FakeInspector(alive: [100])
        let result = await terminator(ScriptedFileDiscovery([[h], []]), inspector).terminate(h, holding: path)
        XCTAssertEqual(result, .terminated)
        XCTAssertEqual(inspector.signals.get(), [SIGTERM])
        XCTAssertEqual(result.message(for: h, path: path), "“data.db” freed — Docker (PID 100) was terminated.")
    }

    func testAnotherProcessHoldingItNowMeansTargetChangedAndNothingIsKilled() async {
        let inspector = FakeInspector(alive: [100, 200])
        let result = await terminator(ScriptedFileDiscovery([[holder(200)]]), inspector).terminate(holder(100), holding: path)
        XCTAssertEqual(result, .targetChanged)
        XCTAssertTrue(inspector.signals.get().isEmpty)
    }

    func testFileNoLongerHeldMapsToReleasedOrExited() async {
        let alive = FakeInspector(alive: [100]), dead = FakeInspector(alive: [])
        let r1 = await terminator(ScriptedFileDiscovery([[]]), alive).terminate(holder(100), holding: path)
        let r2 = await terminator(ScriptedFileDiscovery([[]]), dead).terminate(holder(100), holding: path)
        XCTAssertEqual(r1, .resourceAlreadyReleased)
        XCTAssertEqual(r2, .alreadyExited)
        XCTAssertTrue(alive.signals.get().isEmpty && dead.signals.get().isEmpty)
    }

    func testPIDReuseNeverSignals() async {
        let h = holder(100, start: 1000)
        let inspector = FakeInspector(alive: [100], starts: [100: 9999])
        let result = await terminator(ScriptedFileDiscovery([[h]]), inspector).terminate(h, holding: path)
        XCTAssertEqual(result, .targetChanged)
        XCTAssertTrue(inspector.signals.get().isEmpty)
    }

    func testMissingStartTimeNeverSignals() async {
        let h = holder(100, start: nil)
        let inspector = FakeInspector(alive: [100])
        let result = await terminator(ScriptedFileDiscovery([[h]]), inspector).terminate(h, holding: path)
        guard case .failed(let reason) = result else { return XCTFail("expected .failed, got \(result)") }
        XCTAssertTrue(reason.contains("verify"))
        XCTAssertTrue(inspector.signals.get().isEmpty)
    }

    func testNameMismatchIsTargetChanged() async {
        let inspector = FakeInspector(alive: [100])
        let result = await terminator(ScriptedFileDiscovery([[holder(100, name: "other")]]), inspector).terminate(holder(100), holding: path)
        XCTAssertEqual(result, .targetChanged)
    }

    func testReplacementHolderIsNotReportedAsFreed() async {
        let h = holder(100)
        let inspector = FakeInspector(alive: [100, 200])
        let result = await terminator(ScriptedFileDiscovery([[h], [holder(200, name: "sqlite3")]]), inspector).terminate(h, holding: path)
        guard case .failed(let reason) = result else { return XCTFail("expected .failed, got \(result)") }
        XCTAssertTrue(reason.contains("another process") && reason.contains("200"), reason)
    }

    func testStillHeldAfterExitIsReported() async {
        let h = holder(100)
        let result = await terminator(ScriptedFileDiscovery([[h]]), FakeInspector(alive: [100])).terminate(h, holding: path)
        guard case .failed = result else { return XCTFail("expected .failed, got \(result)") }
    }

    func testNoAutomaticEscalationAndForceRevalidates() async {
        let h = holder(100)
        let stubborn = FakeInspector(alive: [100]); stubborn.diesOnSignal = false
        let r1 = await terminator(ScriptedFileDiscovery([[h]]), stubborn).terminate(h, holding: path)
        XCTAssertEqual(r1, .stillRunning)
        XCTAssertEqual(stubborn.signals.get(), [SIGTERM], "SIGKILL must require an explicit call")

        let inspector = FakeInspector(alive: [100, 300])
        let changed = await terminator(ScriptedFileDiscovery([[holder(300)]]), inspector).forceTerminate(h, holding: path)
        XCTAssertEqual(changed, .targetChanged)
        XCTAssertTrue(inspector.signals.get().isEmpty)

        let ok = FakeInspector(alive: [100])
        let r3 = await terminator(ScriptedFileDiscovery([[h], []]), ok).forceTerminate(h, holding: path)
        XCTAssertEqual(r3, .terminated)
        XCTAssertEqual(ok.signals.get(), [SIGKILL])
    }

    func testPermissionDeniedAndScanFailure() async {
        let h = holder(100)
        let denied = FakeInspector(alive: [100]); denied.signalError = EPERM
        let r1 = await terminator(ScriptedFileDiscovery([[h]]), denied).terminate(h, holding: path)
        XCTAssertEqual(r1, .permissionDenied)

        let d = ScriptedFileDiscovery([[h]]); d.failure = FileLockError.commandFailed("boom")
        let inspector = FakeInspector(alive: [100])
        let r2 = await terminator(d, inspector).terminate(h, holding: path)
        guard case .failed = r2 else { return XCTFail("expected .failed") }
        XCTAssertTrue(inspector.signals.get().isEmpty)
    }

    func testPermissionCapabilityForHolders() {
        let perms = PermissionService(currentUser: "me", ownPID: 999)
        XCTAssertEqual(perms.capability(for: holder(5, user: "me")), .canTerminate)
        XCTAssertEqual(perms.capability(for: holder(5, user: "root")), .protected)
        XCTAssertEqual(perms.capability(for: holder(5, user: "alice")), .permissionRequired)
        XCTAssertEqual(perms.capability(for: holder(1, user: "me")), .protected)
    }
}
