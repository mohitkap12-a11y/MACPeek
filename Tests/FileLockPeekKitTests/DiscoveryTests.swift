import XCTest
@testable import FileLockPeekKit
@testable import MacPeekCore

final class FileLockDiscoveryTests: XCTestCase {
    private var tempDir: URL!
    private var tempFile: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("macpeek-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempFile = tempDir.appendingPathComponent("data.db")
        try Data("x".utf8).write(to: tempFile)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tempDir) }

    private func resolved(_ url: URL) -> String { url.resolvingSymlinksInPath().path }

    func testFileUsesExactMatchWithOptionTerminatorAndResolvedPath() async throws {
        let runner = RecordingRunner(output: CommandOutput(stdout: try fixture("file_single"), stderr: "", status: 0))
        let holders = try await LsofFileLockDiscovery(runner: runner, ownPID: 1).holders(of: tempFile.path)
        XCTAssertEqual(holders.map(\.pid), [18432])
        let (exe, args) = try XCTUnwrap(runner.calls.get().first)
        XCTAssertEqual(exe, "/usr/sbin/lsof")
        XCTAssertEqual(args, ["-nP", "+c", "0", "-FpcLftn", "--", resolved(tempFile)])
    }

    func testFolderUsesRecursiveScan() async throws {
        let runner = RecordingRunner(output: CommandOutput(stdout: try fixture("dir_scan"), stderr: "", status: 0))
        let holders = try await LsofFileLockDiscovery(runner: runner, ownPID: 1).holders(of: tempDir.path)
        XCTAssertEqual(holders.count, 3)
        XCTAssertEqual(runner.calls.get().first?.1.suffix(2).map { $0 }, ["+D", resolved(tempDir)])
    }

    func testPathValidation() async {
        let discovery = LsofFileLockDiscovery(runner: RecordingRunner())
        for bad in ["relative/path.txt", "", "-rf", "~/file"] {
            do { _ = try await discovery.holders(of: bad); XCTFail("expected invalidPath for \(bad)") }
            catch { guard case FileLockError.invalidPath = error else { return XCTFail("wrong error \(error)") } }
        }
        do { _ = try await discovery.holders(of: "/path/with\0nul"); XCTFail("expected throw") }
        catch { guard case FileLockError.invalidPath = error else { return XCTFail("wrong error \(error)") } }
    }

    func testMissingPathIsNotFoundAndNeverRunsLsof() async {
        let runner = RecordingRunner()
        do {
            _ = try await LsofFileLockDiscovery(runner: runner).holders(of: tempDir.appendingPathComponent("nope.txt").path)
            XCTFail("expected throw")
        } catch {
            guard case FileLockError.notFound = error else { return XCTFail("wrong error \(error)") }
        }
        XCTAssertTrue(runner.calls.get().isEmpty)
    }

    func testStatus1WithNoOutputMeansNothingHoldsIt() async throws {
        let runner = RecordingRunner(output: CommandOutput(stdout: "", stderr: "", status: 1))
        let holders = try await LsofFileLockDiscovery(runner: runner).holders(of: tempFile.path)
        XCTAssertTrue(holders.isEmpty)
    }

    func testFailuresAreNeverMistakenForNothingHoldsIt() async {
        let cases = [
            CommandOutput(stdout: "", stderr: "lsof: boom", status: 2),
            CommandOutput(stdout: "p1\ncx\nf3r\ntREG\nn/a\n", stderr: "lsof: killed", status: 2), // partial output on failure
            CommandOutput(stdout: "", stderr: "lsof: WARNING: can't stat() fs", status: 1),
        ]
        for output in cases {
            do {
                _ = try await LsofFileLockDiscovery(runner: RecordingRunner(output: output)).holders(of: tempFile.path)
                XCTFail("expected throw for status \(output.status)")
            } catch {
                guard case FileLockError.commandFailed = error else { return XCTFail("wrong error \(error)") }
            }
        }
    }

    func testStatus1WithDataAndWarningsStillParses() async throws {
        let output = CommandOutput(stdout: try fixture("file_single"), stderr: "lsof: WARNING: can't stat()", status: 1)
        let holders = try await LsofFileLockDiscovery(runner: RecordingRunner(output: output)).holders(of: tempFile.path)
        XCTAssertEqual(holders.count, 1)
    }

    func testRunnerErrorIsWrapped() async {
        let runner = RecordingRunner(); runner.error = CommandError.timedOut("lsof")
        do { _ = try await LsofFileLockDiscovery(runner: runner).holders(of: tempFile.path); XCTFail("expected throw") }
        catch { guard case FileLockError.commandFailed = error else { return XCTFail("wrong error \(error)") } }
    }

    func testServiceEnrichesStartTimeForPIDReuseProtection() async throws {
        let discovery = ScriptedFileDiscovery([[holder(100, start: nil)]])
        let inspector = FakeInspector(alive: [100], starts: [100: 777])
        let holders = try await FileLockService(discovery: discovery, inspector: inspector).holders(of: "/x")
        XCTAssertEqual(holders.first?.startTime, 777)
    }
}
