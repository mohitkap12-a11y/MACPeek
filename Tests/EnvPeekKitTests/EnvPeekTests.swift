import XCTest
@testable import EnvPeekKit

final class ProcArgsParserTests: XCTestCase {
    private func buffer(argc: Int32, _ parts: [String], padding: Int = 3) -> [UInt8] {
        var bytes = withUnsafeBytes(of: argc) { Array($0) }
        bytes += Array(parts[0].utf8) + [0] + [UInt8](repeating: 0, count: padding)
        for part in parts.dropFirst() { bytes += Array(part.utf8) + [0] }
        return bytes
    }

    func testExecutableArgumentsAndEnvironment() throws {
        let bytes = buffer(argc: 2, ["/usr/local/bin/tool", "tool", "--flag", "A=1", "B=two=three", "EMPTY=", "NOEQUALS", "=novalue"])
        let parsed = try XCTUnwrap(ProcArgsParser.parse(bytes))
        XCTAssertEqual(parsed.executable, "/usr/local/bin/tool")
        XCTAssertEqual(parsed.arguments, ["tool", "--flag"])
        XCTAssertEqual(parsed.environment, [
            EnvVariable(name: "A", value: "1"),
            EnvVariable(name: "B", value: "two=three"),
            EnvVariable(name: "EMPTY", value: ""),
        ])
    }

    func testUnicodeValuesAndTheEndOfTheEnvironmentBlock() throws {
        let bytes = buffer(argc: 1, ["/bin/x", "x", "GREETING=héllo ✓", "", "AFTER=ignored"])
        let parsed = try XCTUnwrap(ProcArgsParser.parse(bytes))
        XCTAssertEqual(parsed.environment, [EnvVariable(name: "GREETING", value: "héllo ✓")])
    }

    func testRepeatedNamesGetDistinctIDsSoRowsAndRevealStateStayApart() throws {
        let bytes = buffer(argc: 1, ["/bin/x", "x", "A=1", "B=2", "A=3", "A=4"])
        let parsed = try XCTUnwrap(ProcArgsParser.parse(bytes))
        let ids: [String] = parsed.environment.map { $0.id }
        let values: [String] = parsed.environment.map { $0.value }
        XCTAssertEqual(ids, ["A", "B", "A#1", "A#2"])
        XCTAssertEqual(Set(ids).count, 4)
        XCTAssertEqual(values, ["1", "2", "3", "4"])
    }

    func testNoEnvironment() throws {
        let parsed = try XCTUnwrap(ProcArgsParser.parse(buffer(argc: 1, ["/bin/x", "x"])))
        XCTAssertTrue(parsed.environment.isEmpty)
    }

    func testGarbageIsRejected() {
        XCTAssertNil(ProcArgsParser.parse([]))
        XCTAssertNil(ProcArgsParser.parse([1, 0]))
        XCTAssertNil(ProcArgsParser.parse(withUnsafeBytes(of: Int32(-5)) { Array($0) } + [65, 0]))
    }

    func testTruncatedBufferDoesNotCrash() {
        var bytes = buffer(argc: 5, ["/bin/x", "only-one-arg"])
        bytes.removeLast(3)
        XCTAssertNotNil(ProcArgsParser.parse(bytes))
    }
}

final class VariableTests: XCTestCase {
    func testSensitiveNames() {
        for name in ["GITHUB_TOKEN", "AWS_SECRET_ACCESS_KEY", "DB_PASSWORD", "MY_API_KEY", "STRIPE_KEY", "npm_config_authtoken", "SESSION_COOKIE"] {
            XCTAssertTrue(EnvVariable.looksSensitive(name), name)
        }
        for name in ["PATH", "HOME", "SSH_AUTH_SOCK", "TERM_SESSION_ID", "SECURITYSESSIONID", "LANG", "KEYBOARD_LAYOUT", "SHELL"] {
            XCTAssertFalse(EnvVariable.looksSensitive(name), name)
        }
    }

    func testAssignmentAndSources() {
        XCTAssertEqual(EnvVariable(name: "A", value: "b c").assignment, "A=b c")
        XCTAssertEqual(EnvSource.macPeek.label, "MacPeek's own environment")
        XCTAssertNotNil(EnvSource.macPeek.caveat)
        XCTAssertEqual(EnvSource.process(pid: 42, name: "node").label, "Process node (PID 42)")
        XCTAssertEqual(EnvSource.process(pid: 42, name: nil).label, "Process (PID 42)")
        XCTAssertNil(EnvSource.process(pid: 1, name: nil).caveat)
    }

    func testMacPeekEnvironmentIsSortedByName() {
        let vars = MacPeekEnvironment.variables(["B": "2", "A": "1", "C": "3"])
        XCTAssertEqual(vars.map(\.name), ["A", "B", "C"])
    }

    func testHiddenValuesCannotBeProbedBySearch() {
        let vars = [EnvVariable(name: "API_TOKEN", value: "hunter2-secret"), EnvVariable(name: "HOME", value: "/Users/me")]
        XCTAssertTrue(EnvSearch.filter(vars, query: "hunter2").isEmpty, "a masked value is not searchable")
        XCTAssertEqual(EnvSearch.filter(vars, query: "api_token").map(\.name), ["API_TOKEN"], "its name still is")
        XCTAssertEqual(EnvSearch.filter(vars, query: "hunter2", revealedIDs: ["API_TOKEN"]).map(\.name), ["API_TOKEN"])
        XCTAssertEqual(EnvSearch.filter(vars, query: "/users").map(\.name), ["HOME"], "ordinary values stay searchable")
    }

    func testSearchMatchesNameOrValueAndSorts() {
        let vars = [EnvVariable(name: "ZED", value: "nvm"), EnvVariable(name: "path", value: "/usr/bin"), EnvVariable(name: "NODE_ENV", value: "dev")]
        XCTAssertEqual(EnvSearch.filter(vars, query: "").map(\.name), ["NODE_ENV", "path", "ZED"])
        XCTAssertEqual(EnvSearch.filter(vars, query: "PATH").map(\.name), ["path"])
        XCTAssertEqual(EnvSearch.filter(vars, query: "usr").map(\.name), ["path"])
        XCTAssertEqual(EnvSearch.filter(vars, query: "node dev").map(\.name), ["NODE_ENV"])
        XCTAssertTrue(EnvSearch.filter(vars, query: "node nothing").isEmpty)
    }
}

final class PathAnalyzerTests: XCTestCase {
    func testDuplicatesMissingEmptyAndRelativeEntries() {
        let entries = PathAnalyzer.analyze("/a:/b::/a:rel/dir:~/bin") { $0 != "/b" }
        XCTAssertEqual(entries.map(\.path), ["/a", "/b", "", "/a", "rel/dir", "~/bin"])
        XCTAssertEqual(entries[0].notes, [])
        XCTAssertEqual(entries[1].notes, ["Does not exist"])
        XCTAssertTrue(entries[2].isEmpty)
        XCTAssertEqual(entries[2].notes, ["Empty entry (means the current directory)"])
        XCTAssertEqual(entries[3].duplicateOf, 0)
        XCTAssertEqual(entries[3].notes, ["Duplicate of entry 1"])
        XCTAssertTrue(entries[4].isRelative)
        XCTAssertNil(entries[4].exists, "a relative entry depends on the user's working directory and is not checked")
        XCTAssertEqual(entries[4].notes, ["Relative path"])
        XCTAssertFalse(entries[5].isRelative, "~ is expanded by the shell")
    }

    func testTheRealPathFromAMacHasADuplicateHomebrewEntry() {
        let path = "/Users/<user>/.opencode/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
        let entries = PathAnalyzer.analyze(path) { _ in true }
        XCTAssertEqual(entries.count, 9)
        XCTAssertEqual(entries.last?.duplicateOf, 1)
        XCTAssertEqual(entries.filter { $0.duplicateOf != nil }.count, 1)
    }

    func testPathLikeNames() {
        XCTAssertTrue(PathAnalyzer.isPathLike("PATH"))
        XCTAssertTrue(PathAnalyzer.isPathLike("manpath"))
        XCTAssertFalse(PathAnalyzer.isPathLike("HOME"))
    }
}

final class LiveEnvironmentReaderTests: XCTestCase {
    func testReadsThisProcessesOwnEnvironment() throws {
        let me = Int(ProcessInfo.processInfo.processIdentifier)
        let args: ProcessArguments
        do { args = try SystemProcessEnvironmentReader().read(pid: me) } catch { throw XCTSkip("process environment unavailable here: \(error)") }
        XCTAssertNotNil(args.executable)
        XCTAssertFalse(args.arguments.isEmpty)
        XCTAssertTrue(args.environment.contains { $0.name == "PATH" }, "a test process always starts with PATH")
    }

    func testOutOfRangePIDsAreErrorsNotCrashes() {
        for pid in [0, -1, 2_147_483_648, Int.max] {
            XCTAssertThrowsError(try SystemProcessEnvironmentReader().read(pid: pid), "pid \(pid)") {
                XCTAssertEqual($0 as? EnvError, .noSuchProcess)
            }
        }
    }

    func testAProcessThatDoesNotExistIsAnError() {
        XCTAssertThrowsError(try SystemProcessEnvironmentReader().read(pid: 2_000_000_000))
    }
}
