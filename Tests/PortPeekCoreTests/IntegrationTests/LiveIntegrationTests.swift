import XCTest
@testable import PortPeekCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// End-to-end tests against the real OS: a helper process listens on a TCP port, PortPeek
/// finds it, and KillService frees it. They need `lsof`, so they are skipped where it is absent.
final class LiveIntegrationTests: XCTestCase {
    private let lsofPath = "/usr/sbin/lsof"

    private func requireLsof() throws {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: lsofPath), "lsof not available")
    }

    /// Spawns `python3` listening on an ephemeral port, returning the process and the port.
    private func spawnListener() throws -> (Process, Int) {
        let script = "import socket,sys,time\ns=socket.socket();s.bind(('127.0.0.1',0));s.listen(5)\nprint(s.getsockname()[1],flush=True)\ntime.sleep(120)"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-c", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let line = String(decoding: pipe.fileHandleForReading.availableData, as: UTF8.self)
        guard let port = Int(line.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            process.terminate()
            throw XCTSkip("python3 listener unavailable")
        }
        return (process, port)
    }

    func testDetectSearchAndTerminate() async throws {
        try requireLsof()
        let (process, port) = try spawnListener()
        defer { if process.isRunning { process.terminate() } }

        let service = PortService()
        let ports = try await service.scan()
        let found = try XCTUnwrap(ports.first { $0.port == port && $0.pid == Int(process.processIdentifier) })
        XCTAssertNotNil(found.startTime)
        XCTAssertEqual(PortSearch.filter(ports, query: String(port)).first?.port, port)

        let kill = KillService(discovery: LsofPortDiscovery())
        let result = await kill.terminate(found)
        XCTAssertEqual(result, .terminated)
        XCTAssertFalse(process.isRunning)
        let after = try await service.scan()
        XCTAssertFalse(after.contains { $0.port == port && $0.pid == found.pid })
    }

    func testMultipleListenersAreAllDetected() async throws {
        try requireLsof()
        let a = try spawnListener(), b = try spawnListener()
        defer { a.0.terminate(); b.0.terminate() }
        let scanned = try await PortService().scan()
        let ports = Set(scanned.map(\.port))
        XCTAssertTrue(ports.contains(a.1))
        XCTAssertTrue(ports.contains(b.1))
    }

    func testProcessThatExitsBetweenDiscoveryAndKill() async throws {
        try requireLsof()
        let (process, port) = try spawnListener()
        defer { if process.isRunning { process.terminate() } }
        let scan = try await PortService().scan()
        let found = try XCTUnwrap(scan.first { $0.port == port })
        process.terminate()
        process.waitUntilExit()
        let result = await KillService(discovery: LsofPortDiscovery()).terminate(found)
        XCTAssertTrue(result == .alreadyExited || result == .portAlreadyReleased, "got \(result)")
    }

    func testCannotKillRootOwnedProcessWithoutPermission() async throws {
        try XCTSkipIf(getuid() == 0, "running as root")
        // PID 1 is always refused before any signal is sent.
        let target = PortInfo(port: 1, protocolType: .tcp, address: "*", processName: "launchd", pid: 1)
        let result = await KillService(discovery: ScriptedDiscovery([[target]])).terminate(target)
        guard case .failed = result else { return XCTFail("expected refusal, got \(result)") }
    }
}
