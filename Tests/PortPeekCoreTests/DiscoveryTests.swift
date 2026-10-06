import XCTest
@testable import PortPeekCore

final class DiscoveryTests: XCTestCase {
    func testLsofDiscoveryParsesRunnerOutput() async throws {
        let out = CommandOutput(stdout: try fixture("tcp_ipv4"), stderr: "", status: 0)
        let ports = try await LsofPortDiscovery(runner: FakeRunner(output: out)).discover()
        XCTAssertEqual(ports.map(\.port), [3000])
    }

    func testExitStatus1WithNoOutputIsEmptyList() async throws {
        let out = CommandOutput(stdout: "", stderr: "", status: 1)
        let ports = try await LsofPortDiscovery(runner: FakeRunner(output: out)).discover()
        XCTAssertTrue(ports.isEmpty)
    }

    func testRealFailureThrows() async {
        let out = CommandOutput(stdout: "", stderr: "lsof: boom", status: 2)
        do {
            _ = try await LsofPortDiscovery(runner: FakeRunner(output: out)).discover()
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? PortDiscoveryError, .commandFailed("lsof: boom"))
        }
    }

    func testRunnerErrorIsWrapped() async {
        let runner = FakeRunner(output: CommandOutput(stdout: "", stderr: "", status: 0), error: CocoaError(.fileNoSuchFile))
        do {
            _ = try await LsofPortDiscovery(runner: runner).discover()
            XCTFail("expected throw")
        } catch {
            guard case .commandFailed = error as? PortDiscoveryError else { return XCTFail("wrong error \(error)") }
        }
    }

    func testPortServiceEnrichesStartTime() async throws {
        let inspector = FakeInspector(alive: [100], starts: [100: 123])
        let discovery = ScriptedDiscovery([[port(3000, pid: 100)]])
        let ports = try await PortService(discovery: discovery, inspector: inspector).scan()
        XCTAssertEqual(ports.first?.startTime, 123)
    }

    func testPermissionCapabilities() {
        let svc = PermissionService(currentUser: "me", ownPID: 999)
        XCTAssertEqual(svc.capability(for: port(1, pid: 50, user: "me")), .canTerminate)
        XCTAssertEqual(svc.capability(for: port(1, pid: 50, user: "root")), .protected)
        XCTAssertEqual(svc.capability(for: port(1, pid: 50, user: "alice")), .permissionRequired)
        XCTAssertEqual(svc.capability(for: port(1, pid: 1, user: "me")), .protected)
        XCTAssertEqual(svc.capability(for: port(1, pid: 999, user: "me")), .protected)
    }
}
