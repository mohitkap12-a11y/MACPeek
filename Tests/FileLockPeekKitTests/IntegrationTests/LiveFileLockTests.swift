import XCTest
@testable import FileLockPeekKit
@testable import MacPeekCore

/// Real-OS tests: a helper process holds a temp file open (and another sits in a temp folder), FileLockPeek finds
/// them, and the shared termination service frees the file. They need `lsof` and `python3`, so they skip without them.
final class LiveFileLockTests: XCTestCase {
    private let lsofPath = "/usr/sbin/lsof"

    private func requireTools() throws {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: lsofPath), "lsof not available")
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("macpeek-live-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Starts python3 running `script` (which must print one line when ready) in `cwd`.
    private func spawn(_ script: String, args: [String] = [], cwd: URL? = nil) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-c", script] + args
        if let cwd { process.currentDirectoryURL = cwd }
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let line = String(decoding: pipe.fileHandleForReading.availableData, as: UTF8.self)
        guard line.contains("ready") else { process.terminate(); throw XCTSkip("python3 helper unavailable") }
        return process
    }

    private let holdFile = "import sys,time\nf=open(sys.argv[1],'w')\nprint('ready',flush=True)\ntime.sleep(120)"
    private let holdCwd = "import time\nprint('ready',flush=True)\ntime.sleep(120)"

    func testFindsAndFreesAFileHeldOpen() async throws {
        try requireTools()
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("held.db")
        let process = try spawn(holdFile, args: [file.path])
        defer { if process.isRunning { process.terminate() } }

        let service = FileLockService()
        let holders = try await service.holders(of: file.path)
        let found = try XCTUnwrap(holders.first { $0.pid == Int(process.processIdentifier) }, "helper not found among \(holders.map(\.pid))")
        XCTAssertNotNil(found.startTime)
        XCTAssertEqual(found.primaryKind, .open(.write))

        let result = await FileLockTerminator(discovery: LsofFileLockDiscovery()).terminate(found, holding: file.path)
        XCTAssertEqual(result, .terminated)
        XCTAssertFalse(process.isRunning)
        let after = try await service.holders(of: file.path)
        XCTAssertFalse(after.contains { $0.pid == found.pid })
    }

    func testFolderScanFindsAProcessWhoseWorkingDirectoryIsInside() async throws {
        try requireTools()
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let process = try spawn(holdCwd, cwd: dir)
        defer { if process.isRunning { process.terminate() } }

        let holders = try await FileLockService().holders(of: dir.path)
        let found = try XCTUnwrap(holders.first { $0.pid == Int(process.processIdentifier) }, "helper not found among \(holders.map(\.pid))")
        XCTAssertEqual(found.primaryKind, .workingDirectory)
    }

    func testNothingHoldsAnUntouchedFile() async throws {
        try requireTools()
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("idle.txt")
        try Data("x".utf8).write(to: file)
        let holders = try await FileLockService().holders(of: file.path)
        XCTAssertTrue(holders.isEmpty, "unexpected holders: \(holders)")
    }

    func testProcessThatExitsBetweenScanAndKill() async throws {
        try requireTools()
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("short.db")
        let process = try spawn(holdFile, args: [file.path])
        let scan = try await FileLockService().holders(of: file.path)
        let found = try XCTUnwrap(scan.first { $0.pid == Int(process.processIdentifier) })
        process.terminate(); process.waitUntilExit()
        let result = await FileLockTerminator(discovery: LsofFileLockDiscovery()).terminate(found, holding: file.path)
        XCTAssertTrue(result == .alreadyExited || result == .resourceAlreadyReleased, "got \(result)")
    }
}
