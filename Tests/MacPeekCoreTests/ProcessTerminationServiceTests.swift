import XCTest
@testable import MacPeekCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    func get() -> T { lock.lock(); defer { lock.unlock() }; return value }
    func mutate(_ f: (inout T) -> Void) { lock.lock(); f(&value); lock.unlock() }
}

private final class Inspector: ProcessInspecting, @unchecked Sendable {
    let alive: Box<Set<Int>>
    let starts: [Int: TimeInterval]
    let signals = Box<[Int32]>([])
    var signalError: Int32 = 0
    var diesOnSignal = true
    init(alive: Set<Int>, starts: [Int: TimeInterval]) { self.alive = Box(alive); self.starts = starts }
    func isAlive(pid: Int) -> Bool { alive.get().contains(pid) }
    func startTime(pid: Int) -> TimeInterval? { starts[pid] }
    func signal(pid: Int, signal: Int32) -> Int32 {
        signals.mutate { $0.append(signal) }
        if signalError != 0 { return signalError }
        if diesOnSignal { alive.mutate { $0.remove(pid) } }
        return 0
    }
}

/// A resource whose state is scripted: `checks` are consumed per call (last repeats), same for `releases`.
private final class Resource: TerminationResource, @unchecked Sendable {
    let label = "the thing"
    private let checks: Box<[ResourceCheck]>
    private let releases: Box<[ReleaseState]>
    init(checks: [ResourceCheck], releases: [ReleaseState] = [.released]) {
        self.checks = Box(checks); self.releases = Box(releases)
    }
    private func next<T>(_ box: Box<[T]>) -> T {
        var out: T!
        box.mutate { arr in out = arr.first!; if arr.count > 1 { arr.removeFirst() } }
        return out
    }
    func check(pid: Int) async -> ResourceCheck { next(checks) }
    func releaseState(pid: Int) async -> ReleaseState { next(releases) }
}

final class ProcessTerminationServiceTests: XCTestCase {
    private let target = ProcessTarget(pid: 100, processName: "node", startTime: 50)

    private func service(_ inspector: Inspector) -> ProcessTerminationService {
        ProcessTerminationService(inspector: inspector, gracePeriod: 0.3, forceTimeout: 0.3, pollInterval: 0.02, ownPID: 1)
    }

    func testHappyPathSendsOnlySIGTERM() async {
        let inspector = Inspector(alive: [100], starts: [100: 50])
        let result = await service(inspector).terminate(target, resource: Resource(checks: [.owned(processName: "node")]))
        XCTAssertEqual(result, .terminated)
        XCTAssertEqual(inspector.signals.get(), [SIGTERM])
    }

    func testResourceGoneMapsToExitedOrReleasedWithoutSignalling() async {
        let alive = Inspector(alive: [100], starts: [100: 50])
        let r1 = await service(alive).terminate(target, resource: Resource(checks: [.gone]))
        XCTAssertEqual(r1, .resourceAlreadyReleased)
        let dead = Inspector(alive: [], starts: [:])
        let r2 = await service(dead).terminate(target, resource: Resource(checks: [.gone]))
        XCTAssertEqual(r2, .alreadyExited)
        XCTAssertTrue(alive.signals.get().isEmpty && dead.signals.get().isEmpty)
    }

    func testChangedResourceOrNameNeverSignals() async {
        let inspector = Inspector(alive: [100], starts: [100: 50])
        let r1 = await service(inspector).terminate(target, resource: Resource(checks: [.changed]))
        let r2 = await service(inspector).terminate(target, resource: Resource(checks: [.owned(processName: "python")]))
        XCTAssertEqual(r1, .targetChanged)
        XCTAssertEqual(r2, .targetChanged)
        XCTAssertTrue(inspector.signals.get().isEmpty)
    }

    func testPIDReuseByStartTimeNeverSignals() async {
        let inspector = Inspector(alive: [100], starts: [100: 9999])
        let result = await service(inspector).terminate(target, resource: Resource(checks: [.owned(processName: "node")]))
        XCTAssertEqual(result, .targetChanged)
        XCTAssertTrue(inspector.signals.get().isEmpty)
    }

    func testUnprovableIdentityNeverSignals() async {
        let owned = Resource(checks: [.owned(processName: "node")])
        let noStored = ProcessTarget(pid: 100, processName: "node", startTime: nil)
        let i1 = Inspector(alive: [100], starts: [100: 50])
        let r1 = await service(i1).terminate(noStored, resource: owned)
        let i2 = Inspector(alive: [100], starts: [:])
        let r2 = await service(i2).forceTerminate(target, resource: owned)
        for r in [r1, r2] { guard case .failed = r else { return XCTFail("expected .failed, got \(r)") } }
        XCTAssertTrue(i1.signals.get().isEmpty && i2.signals.get().isEmpty)
    }

    func testUnavailableResourceIsAFailureNotASuccess() async {
        let inspector = Inspector(alive: [100], starts: [100: 50])
        let result = await service(inspector).terminate(target, resource: Resource(checks: [.unavailable("scan failed")]))
        XCTAssertEqual(result, .failed("scan failed"))
        XCTAssertTrue(inspector.signals.get().isEmpty)
    }

    func testPermissionDeniedAndVanishingProcess() async {
        let owned = Resource(checks: [.owned(processName: "node")])
        let denied = Inspector(alive: [100], starts: [100: 50]); denied.signalError = EPERM
        let gone = Inspector(alive: [100], starts: [100: 50]); gone.signalError = ESRCH
        let rDenied = await service(denied).terminate(target, resource: owned)
        let rGone = await service(gone).terminate(target, resource: owned)
        XCTAssertEqual(rDenied, .permissionDenied)
        XCTAssertEqual(rGone, .alreadyExited)
    }

    func testNoAutomaticEscalationToSIGKILL() async {
        let inspector = Inspector(alive: [100], starts: [100: 50]); inspector.diesOnSignal = false
        let result = await service(inspector).terminate(target, resource: Resource(checks: [.owned(processName: "node")]))
        XCTAssertEqual(result, .stillRunning)
        XCTAssertEqual(inspector.signals.get(), [SIGTERM])
    }

    func testForceKillRevalidates() async {
        let inspector = Inspector(alive: [100], starts: [100: 50])
        let changed = await service(inspector).forceTerminate(target, resource: Resource(checks: [.changed]))
        XCTAssertEqual(changed, .targetChanged)
        XCTAssertTrue(inspector.signals.get().isEmpty)
        let ok = await service(inspector).forceTerminate(target, resource: Resource(checks: [.owned(processName: "node")]))
        XCTAssertEqual(ok, .terminated)
        XCTAssertEqual(inspector.signals.get(), [SIGKILL])
    }

    func testReplacementOwnerIsNotReportedAsFreed() async {
        let inspector = Inspector(alive: [100], starts: [100: 50])
        let resource = Resource(checks: [.owned(processName: "node")], releases: [.takenOver(pid: 200)])
        let result = await service(inspector).terminate(target, resource: resource)
        guard case .failed(let reason) = result else { return XCTFail("expected .failed, got \(result)") }
        XCTAssertTrue(reason.contains("another process") && reason.contains("200"), reason)
    }

    func testStillHeldAfterExitIsReported() async {
        let inspector = Inspector(alive: [100], starts: [100: 50])
        let resource = Resource(checks: [.owned(processName: "node")], releases: [.stillHeld])
        let result = await service(inspector).terminate(target, resource: resource)
        guard case .failed = result else { return XCTFail("expected .failed, got \(result)") }
    }

    func testRefusesPID1AndSelf() async {
        let inspector = Inspector(alive: [1, 42], starts: [1: 1, 42: 1])
        let svc = ProcessTerminationService(inspector: inspector, ownPID: 42)
        for pid in [1, 42] {
            let r = await svc.terminate(ProcessTarget(pid: pid, processName: "x", startTime: 1),
                                        resource: Resource(checks: [.owned(processName: "x")]))
            guard case .failed = r else { return XCTFail("expected refusal for \(pid)") }
        }
        XCTAssertTrue(inspector.signals.get().isEmpty)
    }

    func testMessagesAndPermissionMapping() {
        XCTAssertEqual(TerminationResult.terminated.message(for: target, resourceLabel: "port 3000"),
                       "Port 3000 freed — node (PID 100) was terminated.")
        XCTAssertTrue(TerminationResult.permissionDenied.message(for: target, resourceLabel: "x").contains("Permission denied"))
        XCTAssertTrue(TerminationResult.resourceAlreadyReleased.isSuccess)
        XCTAssertFalse(TerminationResult.targetChanged.isSuccess)
        let perms = PermissionService(currentUser: "me", ownPID: 999)
        XCTAssertEqual(perms.capability(pid: 50, user: "me"), .canTerminate)
        XCTAssertEqual(perms.capability(pid: 50, user: nil), .canTerminate)
        XCTAssertEqual(perms.capability(pid: 50, user: "root"), .protected)
        XCTAssertEqual(perms.capability(pid: 50, user: "alice"), .permissionRequired)
        XCTAssertEqual(perms.capability(pid: 1, user: "me"), .protected)
        XCTAssertEqual(perms.capability(pid: 999, user: "me"), .protected)
    }
}
