import XCTest
@testable import ProcessPeekKit
import PortPeekKit
import MacPeekCore

final class PSParserTests: XCTestCase {
    private func entries() throws -> [ProcessEntry] { PSParser.parse(try fixture("ps_sample")) }

    func testRealPsOutputParsesEveryRow() throws {
        let all = try entries()
        XCTAssertEqual(all.count, 41, "the header is skipped and every other row parses")
        XCTAssertEqual(Set(all.map(\.pid)).count, all.count)
    }

    func testLaunchd() throws {
        let launchd = try XCTUnwrap(entries().first { $0.pid == 1 })
        XCTAssertEqual(launchd.ppid, 0)
        XCTAssertEqual(launchd.uid, 0)
        XCTAssertEqual(launchd.user, "root")
        XCTAssertEqual(launchd.state, "Ss")
        XCTAssertEqual(launchd.stateLabel, "Sleeping")
        XCTAssertEqual(launchd.elapsed, "01-05:36:20")
        XCTAssertEqual(launchd.elapsedLabel, "1d 5h")
        XCTAssertEqual(launchd.cpuPercent, 0.0)
        XCTAssertEqual(launchd.residentKB, 4880)
        XCTAssertEqual(launchd.executable, "/sbin/launchd")
        XCTAssertEqual(launchd.name, "launchd")
        XCTAssertEqual(launchd.memoryLabel, "4.8 MB")
    }

    func testStartTimeIsParsedAsLocalTimeIncludingSingleDigitDays() throws {
        // "Mon Oct  5 14:01:58 2026" has two spaces before the day.
        let launchd = try XCTUnwrap(entries().first { $0.pid == 1 })
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: try XCTUnwrap(launchd.startTime))
        XCTAssertEqual([parts.year, parts.month, parts.day, parts.hour, parts.minute, parts.second], [2026, 10, 5, 14, 1, 58])
    }

    func testExecutablePathsWithSpacesAreKeptWhole() throws {
        let helper = try XCTUnwrap(entries().first { $0.pid == 4973 })
        XCTAssertTrue(helper.executable.hasSuffix("Microsoft Edge Helper.app/Contents/MacOS/Microsoft Edge Helper"))
        XCTAssertEqual(helper.name, "Microsoft Edge Helper")
        XCTAssertEqual(helper.uid, 501)
        XCTAssertEqual(helper.user, "<user>")
    }

    func testLoginShellAndRelativePaths() throws {
        let all = try entries()
        let shell = try XCTUnwrap(all.first { $0.pid == 10830 })
        XCTAssertEqual(shell.name, "-zsh")
        let macPeek = try XCTUnwrap(all.first { $0.pid == 15657 })
        XCTAssertEqual(macPeek.name, "MacPeek")
        XCTAssertEqual(macPeek.state, "S+")
    }

    func testGarbageProducesNoRows() {
        XCTAssertTrue(PSParser.parse("").isEmpty)
        XCTAssertTrue(PSParser.parse("PID PPID UID USER STAT STARTED ELAPSED %CPU RSS COMM\nnot a process row").isEmpty)
    }
}

final class FormattingTests: XCTestCase {
    func testElapsedTime() {
        XCTAssertEqual(ElapsedTime.label("01-05:36:20"), "1d 5h")
        XCTAssertEqual(ElapsedTime.label("1-00:00:00"), "1d 0h")
        XCTAssertEqual(ElapsedTime.label("02:48:04"), "2h 48m")
        XCTAssertEqual(ElapsedTime.label("03:26"), "3m 26s")
        XCTAssertEqual(ElapsedTime.label("00:07"), "7s")
        XCTAssertEqual(ElapsedTime.label("garbage"), "garbage")
    }

    func testByteCounts() {
        XCTAssertEqual(ByteCountLabel.kilobytes(640), "640 KB")
        XCTAssertEqual(ByteCountLabel.kilobytes(1024), "1.0 MB")
        XCTAssertEqual(ByteCountLabel.kilobytes(4880), "4.8 MB")
        XCTAssertEqual(ByteCountLabel.kilobytes(24_000), "23 MB")
        XCTAssertEqual(ByteCountLabel.kilobytes(1_500_000), "1.4 GB")
    }
}

final class SnapshotAndSearchTests: XCTestCase {
    private func snapshot() throws -> ProcessSnapshot { ProcessSnapshot(entries: PSParser.parse(try fixture("ps_sample"))) }

    func testParentAndChildren() throws {
        let s = try snapshot()
        let children = s.children(of: 4890)
        XCTAssertEqual(children.count, 5)
        XCTAssertEqual(children.map(\.pid), children.map(\.pid).sorted())
        let child = try XCTUnwrap(s.entry(pid: 4973))
        XCTAssertEqual(s.parent(of: child)?.pid, 4890)
        XCTAssertNil(s.parent(of: try XCTUnwrap(s.entry(pid: 1))), "launchd's parent (0) is not a process")
    }

    func testAncestorsAreCycleSafe() {
        func entry(_ pid: Int, _ ppid: Int) -> ProcessEntry {
            ProcessEntry(pid: pid, ppid: ppid, uid: 0, user: "u", state: "S", startTime: nil, elapsed: "00:01", cpuPercent: 0, residentKB: 1, executable: "/x/p\(pid)")
        }
        let s = ProcessSnapshot(entries: [entry(1, 2), entry(2, 3), entry(3, 1), entry(4, 4)])
        XCTAssertEqual(s.ancestors(of: entry(1, 2)).map(\.pid), [2, 3])
        XCTAssertTrue(s.ancestors(of: entry(4, 4)).isEmpty)
    }

    func testSearchMatchesNamePIDUserAndPathAndRequiresEveryWord() throws {
        let all = try snapshot().entries
        XCTAssertEqual(ProcessSearch.filter(all, query: "4973", ownedBy: nil, sort: .pid).map(\.pid), [4973])
        XCTAssertFalse(ProcessSearch.filter(all, query: "edge", ownedBy: nil, sort: .name).isEmpty)
        XCTAssertTrue(ProcessSearch.filter(all, query: "edge zzzznothing", ownedBy: nil, sort: .name).isEmpty)
        XCTAssertFalse(ProcessSearch.filter(all, query: "root", ownedBy: nil, sort: .name).isEmpty)
        XCTAssertEqual(ProcessSearch.filter(all, query: "", ownedBy: nil, sort: .name).count, all.count)
    }

    func testOwnedFilterAndSorting() throws {
        let all = try snapshot().entries
        let mine = ProcessSearch.filter(all, query: "", ownedBy: 501, sort: .cpu)
        XCTAssertTrue(mine.allSatisfy { $0.uid == 501 })
        XCTAssertTrue(mine.count < all.count)
        XCTAssertEqual(mine.map(\.cpuPercent), mine.map(\.cpuPercent).sorted(by: >))
        let byMemory = ProcessSearch.filter(all, query: "", ownedBy: nil, sort: .memory)
        XCTAssertEqual(byMemory.map(\.residentKB), byMemory.map(\.residentKB).sorted(by: >))
        let byName = ProcessSearch.filter(all, query: "", ownedBy: nil, sort: .name)
        XCTAssertEqual(byName.map { $0.name.lowercased() }, byName.map { $0.name.lowercased() }.sorted())
    }
}

final class ListerTests: XCTestCase {
    private let started = "Mon Oct  5 20:26:33 2026"

    private func entry(pid: Int = 42, start: String? = "Mon Oct  5 20:26:33 2026") -> ProcessEntry {
        ProcessEntry(pid: pid, ppid: 1, uid: 501, user: "me", state: "S", startTime: start.flatMap(PSParser.date(from:)),
                     elapsed: "01:00", cpuPercent: 0, residentKB: 1, executable: "/usr/local/bin/node")
    }

    private func lister(_ runner: CommandRunning, ports: Result<[PortInfo], Error> = .success([])) -> PSProcessLister {
        PSProcessLister(runner: runner, ports: FakePorts(result: ports))
    }

    func testSnapshotRunsPsInTheCLocaleWithTheVerifiedColumns() async throws {
        let fixture = try fixture("ps_sample")
        let runner = RoutedRunner { _ in output(fixture) }
        let snapshot = try await lister(runner).snapshot()
        XCTAssertEqual(snapshot.entries.count, 41)
        XCTAssertEqual(runner.calls.first?.0, "/usr/bin/env")
        // LC_ALL=C: ps prints lstart in the user's locale otherwise, which the parser cannot read.
        XCTAssertEqual(runner.calls.first?.1, ["LC_ALL=C", "/bin/ps", "-axo", "pid,ppid,uid,user,state,lstart,etime,%cpu,rss,comm"])
    }

    func testPsFailureCarriesStderr() async {
        let runner = RoutedRunner { _ in failure("ps broke") }
        do {
            _ = try await lister(runner).snapshot()
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? ProcessListError, .commandFailed("ps broke"))
        }
    }

    func testRowsThatAllFailToParseAreAnErrorNotAnEmptyList() async {
        let runner = RoutedRunner { _ in output("  PID  PPID\n1 0 root un-parseable row in some other locale\n") }
        do {
            _ = try await lister(runner).snapshot()
            XCTFail("expected throw")
        } catch {
            guard case ProcessListError.commandFailed = error else { return XCTFail("wrong error \(error)") }
        }
    }

    func testDetailsHaveCommandLineAndOnlyThisProcessesPorts() async throws {
        let mine = PortInfo(port: 3000, protocolType: .tcp, address: "*", processName: "node", pid: 42)
        let other = PortInfo(port: 5000, protocolType: .tcp, address: "*", processName: "other", pid: 43)
        let line = started + "  /usr/local/bin/node server.js --port 3000\n"
        let runner = RoutedRunner { _ in output(line) }
        let details = try await lister(runner, ports: .success([mine, other])).details(for: entry())
        XCTAssertFalse(details.processChanged)
        XCTAssertEqual(details.commandLine, "/usr/local/bin/node server.js --port 3000")
        XCTAssertEqual(details.listeningPorts, [mine])
        XCTAssertNil(details.portsNote)
        XCTAssertEqual(runner.calls.first?.1, ["LC_ALL=C", "/bin/ps", "-ww", "-o", "lstart=,args=", "-p", "42"])
        XCTAssertEqual(runner.calls.count, 2, "identity is confirmed before and after the slow lsof run")
    }

    func testAReusedPIDNeverShowsTheReplacementsDetails() async throws {
        let replacement = "Tue Oct  6 09:00:00 2026  /bin/other --secret-flag\n"
        let runner = RoutedRunner { _ in output(replacement) }
        let port = PortInfo(port: 1, protocolType: .tcp, address: "*", processName: "other", pid: 42)
        let details = try await lister(runner, ports: .success([port])).details(for: entry())
        XCTAssertTrue(details.processChanged)
        XCTAssertNil(details.commandLine)
        XCTAssertTrue(details.listeningPorts.isEmpty)
    }

    func testAPIDReusedWhileLsofRanIsCaught() async throws {
        let box = SequenceBox([output(started + "  /usr/local/bin/node\n"), output("Tue Oct  6 09:00:00 2026  /bin/other\n")])
        let runner = RoutedRunner { _ in box.next() }
        let details = try await lister(runner).details(for: entry())
        XCTAssertTrue(details.processChanged)
        XCTAssertNil(details.commandLine)
    }

    func testAnExitedProcessAndAnUnknownStartTimeAreBothChanged() async throws {
        let gone = RoutedRunner { _ in failure("", status: 1) }
        let exited = try await lister(gone).details(for: entry())
        XCTAssertTrue(exited.processChanged)

        let alive = RoutedRunner { _ in output(self.started + "  /usr/local/bin/node\n") }
        let unknown = try await lister(alive).details(for: entry(start: nil))
        XCTAssertTrue(unknown.processChanged, "without a start time the process cannot be confirmed, so nothing is shown")
    }

    func testPortFailureIsANote() async throws {
        let runner = RoutedRunner { _ in output(self.started + "  /usr/local/bin/node\n") }
        let details = try await lister(runner, ports: .failure(PortDiscoveryError.commandFailed("lsof failed"))).details(for: entry())
        XCTAssertFalse(details.processChanged)
        XCTAssertNotNil(details.portsNote)
        XCTAssertEqual(details.commandLine, "/usr/local/bin/node")
    }

    func testCancellationPropagates() async {
        let runner = RoutedRunner { _ in output(self.started + "  /usr/local/bin/node\n") }
        do {
            _ = try await lister(runner, ports: .failure(CommandError.cancelled)).details(for: entry())
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? CommandError, .cancelled)
        }
    }
}

final class StartTimeTests: XCTestCase {
    func testDatesAgreeToTheSecond() {
        let a = PSParser.date(from: "Mon Oct  5 20:26:33 2026")
        XCTAssertTrue(PSProcessLister.sameProcess(a, a))
        XCTAssertTrue(PSProcessLister.sameProcess(a, a?.addingTimeInterval(1)))
        XCTAssertFalse(PSProcessLister.sameProcess(a, a?.addingTimeInterval(30)))
        XCTAssertFalse(PSProcessLister.sameProcess(nil, a))
        XCTAssertFalse(PSProcessLister.sameProcess(a, nil))
    }
}
