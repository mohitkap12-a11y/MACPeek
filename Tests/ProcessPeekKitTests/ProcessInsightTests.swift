import XCTest
@testable import ProcessPeekKit
import MacPeekCore

final class ProcessInsightTests: XCTestCase {
    private func entry(_ pid: Int, ppid: Int, uid: Int = 501, name: String) -> ProcessEntry {
        ProcessEntry(pid: pid, ppid: ppid, uid: uid, user: uid == 501 ? "me" : "root", state: "S", startTime: nil, elapsed: "01:00",
                     cpuPercent: 0, residentKB: 1000, executable: name)
    }

    private var snapshot: ProcessSnapshot {
        ProcessSnapshot(entries: [entry(1, ppid: 0, uid: 0, name: "/sbin/launchd"), entry(4410, ppid: 1, name: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"),
                                  entry(4500, ppid: 4410, name: "login"), entry(4510, ppid: 4500, name: "-zsh"), entry(4600, ppid: 4510, name: "node"),
                                  entry(5120, ppid: 1, name: "/opt/homebrew/opt/postgresql@16/bin/postgres"), entry(5121, ppid: 5120, name: "postgres"),
                                  entry(6000, ppid: 1, name: "/usr/libexec/somed"), entry(7000, ppid: 0, uid: 0, name: "kernel_task")])
    }

    func testParsers() throws {
        let jobs = LaunchctlListParser.parse(try fixture("launchctl_list"))
        XCTAssertEqual(jobs.count, 5)
        XCTAssertEqual(jobs[2].bundleIdentifier, "com.apple.Terminal")
        XCTAssertNil(jobs[0].pid)
        XCTAssertEqual(jobs[4].lastExitStatus, 78)
        let details = try XCTUnwrap(LaunchctlPrintParser.parse(try fixture("launchctl_print")))
        XCTAssertEqual(details.plistPath, "/Users/me/Library/LaunchAgents/homebrew.mxcl.postgresql@16.plist")
        XCTAssertEqual(details.keepAlive, true)
        XCTAssertEqual(details.runAtLoad, true)
        let files = LsofOpenFilesParser.parse(try fixture("lsof_pid"))
        XCTAssertEqual(files.map(\.descriptor), ["cwd", "txt", "7u", "8u"])
        XCTAssertEqual(files[2].isNetwork, true)
        XCTAssertEqual(files[0].type, "DIR")
    }

    private func reader() throws -> (SystemProcessInsightReader, RoutedRunner) {
        let list = try fixture("launchctl_list"), print = try fixture("launchctl_print"), lsof = try fixture("lsof_pid")
        let runner = RoutedRunner { args in
            switch args.first {
            case "list": return output(list)
            case "print": return output(print)
            case "-n": return output(lsof)
            default: return CommandOutput(stdout: "", stderr: "", status: 1)
            }
        }
        return (SystemProcessInsightReader(runner: runner, uid: 501), runner)
    }

    func testOrigins() async throws {
        let (reader, runner) = try reader()
        let snap = snapshot
        let postgres = await reader.origin(of: snap.entry(pid: 5120)!, in: snap)
        XCTAssertEqual(postgres.kind, .launchdJob)
        XCTAssertEqual(postgres.details?.keepAlive, true)
        XCTAssertTrue(runner.calls.contains { $0.1 == ["print", "gui/501/homebrew.mxcl.postgresql@16"] })
        let terminal = await reader.origin(of: snap.entry(pid: 4410)!, in: snap)
        XCTAssertEqual(terminal.kind, .application)
        let node = await reader.origin(of: snap.entry(pid: 4600)!, in: snap)
        XCTAssertEqual(node.kind, .descendant)
        XCTAssertEqual(node.viaPID, 4410)
        XCTAssertEqual(node.summary, "Started by the app com.apple.Terminal (PID 4410)")
        let daemon = await reader.origin(of: snap.entry(pid: 6000)!, in: snap)
        XCTAssertEqual(daemon.kind, .launchdOther)
        XCTAssertEqual(try JSONDecoder().decode(ProcessOrigin.self, from: JSONEncoder().encode(postgres)), postgres)
    }

    func testKillAdvice() async throws {
        let (reader, _) = try reader()
        let snap = snapshot
        let postgres = KillAdvice.assess(entry: snap.entry(pid: 5120)!, snapshot: snap, origin: await reader.origin(of: snap.entry(pid: 5120)!, in: snap), currentUID: 501)
        XCTAssertEqual(postgres.level, .caution)
        XCTAssertTrue(postgres.reasons.contains { $0.contains("keeps this job alive") })
        XCTAssertTrue(postgres.reasons.contains { $0.contains("1 child process") })
        let node = KillAdvice.assess(entry: snap.entry(pid: 4600)!, snapshot: snap, origin: await reader.origin(of: snap.entry(pid: 4600)!, in: snap), currentUID: 501)
        XCTAssertEqual(node.level, .likelySafe)
        let kernel = KillAdvice.assess(entry: snap.entry(pid: 7000)!, snapshot: snap, origin: nil, currentUID: 501)
        XCTAssertEqual(kernel.level, .avoid)
    }

    func testOpenFiles() async throws {
        let (reader, runner) = try reader()
        let report = try await reader.openFiles(of: snapshot.entry(pid: 5120)!, limit: 3)
        XCTAssertEqual(report.files.count, 3)
        XCTAssertTrue(report.truncated)
        XCTAssertEqual(report.workingDirectory, "/opt/homebrew/var/postgresql@16")
        XCTAssertEqual(runner.calls.last?.1, ["-n", "-P", "-w", "-p", "5120", "-F", "ftn"])
        XCTAssertEqual(try JSONDecoder().decode(OpenFilesReport.self, from: JSONEncoder().encode(report)), report)
    }
}
