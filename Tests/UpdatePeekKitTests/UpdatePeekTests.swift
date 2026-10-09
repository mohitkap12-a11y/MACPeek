import XCTest
@testable import UpdatePeekKit
import MacPeekCore

private final class ScriptedRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [(String, [String])] = []
    let result: Result<CommandOutput, Error>
    init(_ result: Result<CommandOutput, Error>) { self.result = result }
    var calls: [(String, [String])] { lock.lock(); defer { lock.unlock() }; return _calls }
    func run(_ executable: String, _ arguments: [String]) async throws -> CommandOutput {
        lock.lock(); _calls.append((executable, arguments)); lock.unlock()
        return try result.get()
    }
}

private struct FixedLocator: HomebrewLocating {
    let path: String?
    func brewPath() -> String? { path }
}

private struct FixedOS: OperatingSystemProviding {
    func current() -> OperatingSystemInfo { OperatingSystemInfo(major: 15, minor: 1, patch: 0, build: "24B83") }
}

private func ok(_ text: String) -> Result<CommandOutput, Error> { .success(CommandOutput(stdout: text, stderr: "", status: 0)) }

private let sample = """
{"formulae":[{"name":"wget","installed_versions":["1.21.3"],"current_version":"1.24.5","pinned":false,"pinned_version":null},
             {"name":"Git","installed_versions":["2.43.0","2.42.0"],"current_version":"2.44.0"}],
 "casks":[{"name":"firefox","installed_versions":"122.0","current_version":"123.0"}]}
"""

final class OperatingSystemInfoTests: XCTestCase {
    func testVersionFormatting() {
        XCTAssertEqual(OperatingSystemInfo(major: 15, minor: 1, patch: 0, build: "24B83").displayString, "macOS 15.1 (24B83)")
        XCTAssertEqual(OperatingSystemInfo(major: 14, minor: 6, patch: 1, build: nil).displayString, "macOS 14.6.1")
        XCTAssertNil(OperatingSystemInfo(major: 13, minor: 0, patch: 0, build: "").build)
    }

    func testSystemProviderReportsARealVersion() {
        XCTAssertGreaterThan(SystemOperatingSystem().current().major, 0)
    }
}

final class HomebrewParserTests: XCTestCase {
    func testParsesFormulaeAndCasksSortedByName() throws {
        let packages = try HomebrewParser.parse(sample)
        XCTAssertEqual(packages.map(\.name), ["firefox", "Git", "wget"])
        let firefox = try XCTUnwrap(packages.first)
        XCTAssertEqual(firefox.kind, .cask)
        XCTAssertEqual(firefox.installedVersions, ["122.0"])
        XCTAssertEqual(firefox.currentVersion, "123.0")
        XCTAssertEqual(packages[1].installedLabel, "2.43.0, 2.42.0")
    }

    func testEmptyButValidIsNoOutdatedPackages() throws {
        XCTAssertEqual(try HomebrewParser.parse(#"{"formulae":[],"casks":[]}"#), [])
    }

    func testMalformedOrUnexpectedShapesFail() {
        let noInstalled = #"{"formulae":[{"name":"x","current_version":"2"}]}"#
        let nullInstalled = #"{"formulae":[{"name":"x","installed_versions":null,"current_version":"2"}]}"#
        let numberInstalled = #"{"casks":[{"name":"x","installed_versions":5,"current_version":"2"}]}"#
        for bad in ["", "not json", "[]", "{}", #"{"formulae":[{"name":"x"}]}"#, #"{"formulae":"nope"}"#,
                    noInstalled, nullInstalled, numberInstalled] {
            XCTAssertThrowsError(try HomebrewParser.parse(bad), bad) { XCTAssertEqual($0 as? UpdatePeekError, .malformedData) }
        }
    }

    func testLocalisedOrChattyOutputIsNotParsedAsData() {
        XCTAssertThrowsError(try HomebrewParser.parse("Warning: something\n" + sample))
    }
}

final class BrewCheckerTests: XCTestCase {
    func testUsesFixedExecutableAndArgumentArray() async throws {
        let runner = ScriptedRunner(ok(sample))
        let checker = BrewOutdatedChecker(runner: runner, locator: FixedLocator(path: "/opt/homebrew/bin/brew"))
        let report = try await checker.outdated()
        XCTAssertEqual(report.packages.count, 3)
        let call = try XCTUnwrap(runner.calls.first)
        XCTAssertEqual(call.0, "/usr/bin/env")
        XCTAssertEqual(call.1, ["HOMEBREW_NO_AUTO_UPDATE=1", "HOMEBREW_NO_ANALYTICS=1", "HOMEBREW_NO_ENV_HINTS=1",
                                "/opt/homebrew/bin/brew", "outdated", "--json=v2"])
    }

    func testMissingHomebrewIsSourceUnavailableAndRunsNothing() async {
        let runner = ScriptedRunner(ok(sample))
        let checker = BrewOutdatedChecker(runner: runner, locator: FixedLocator(path: nil))
        do { _ = try await checker.outdated(); XCTFail("expected error") } catch {
            guard case UpdatePeekError.sourceUnavailable = error else { return XCTFail("wrong error \(error)") }
        }
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testNonZeroExitDoesNotLeakRawOutput() async {
        let runner = ScriptedRunner(.success(CommandOutput(stdout: "", stderr: "Error: /Users/me/secret failed", status: 1)))
        let checker = BrewOutdatedChecker(runner: runner, locator: FixedLocator(path: "/usr/local/bin/brew"))
        do { _ = try await checker.outdated(); XCTFail("expected error") } catch {
            XCTAssertEqual(error as? UpdatePeekError, .operationFailed("Homebrew could not list outdated packages."))
            XCTAssertFalse(error.localizedDescription.contains("secret"))
        }
    }

    func testTimeoutIsReportedNotRaw() async {
        let runner = ScriptedRunner(.failure(CommandError.timedOut("brew")))
        let checker = BrewOutdatedChecker(runner: runner, locator: FixedLocator(path: "/usr/local/bin/brew"))
        do { _ = try await checker.outdated(); XCTFail("expected error") } catch {
            guard case UpdatePeekError.operationFailed = error else { return XCTFail("wrong error \(error)") }
        }
    }
}

final class UpdateStatusServiceTests: XCTestCase {
    private func service(path: String?, runner: CommandRunning) -> UpdateStatusService {
        let locator = FixedLocator(path: path)
        return UpdateStatusService(os: FixedOS(), locator: locator, homebrew: BrewOutdatedChecker(runner: runner, locator: locator))
    }

    func testInitialStateDependsOnlyOnWhetherHomebrewExists() {
        let runner = ScriptedRunner(ok(sample))
        XCTAssertEqual(service(path: nil, runner: runner).initialHomebrewState(), .notInstalled)
        XCTAssertEqual(service(path: "/opt/homebrew/bin/brew", runner: runner).initialHomebrewState(), .notChecked)
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testCheckedStateCarriesPackagesAndTimestamp() async {
        let state = await service(path: "/opt/homebrew/bin/brew", runner: ScriptedRunner(ok(sample))).checkHomebrew()
        guard case .checked(let report) = state else { return XCTFail("expected checked, got \(state)") }
        XCTAssertEqual(report.packages.count, 3)
    }

    func testFailuresAreRetryableAndUnderstandable() async {
        let bad = ScriptedRunner(ok("garbage"))
        let state = await service(path: "/opt/homebrew/bin/brew", runner: bad).checkHomebrew()
        XCTAssertEqual(state, .failed(message: "Homebrew's answer could not be understood.", retryable: true))
    }

    func testHomebrewAbsentIsNotAnError() async {
        let runner = ScriptedRunner(ok(sample))
        let state = await service(path: nil, runner: runner).checkHomebrew()
        XCTAssertEqual(state, .notInstalled)
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testNoticesDoNotClaimAnythingIsUpToDate() {
        let text = (UpdateStatusService.osUpdateNotice + UpdateStatusService.otherAppsNotice).lowercased()
        XCTAssertFalse(text.contains("up to date"))
        XCTAssertFalse(text.contains("no update"))
    }
}

final class UpdateActionTests: XCTestCase {
    private let wget = OutdatedPackage(name: "wget", kind: .formula, installedVersions: ["1"], currentVersion: "2")
    private let firefox = OutdatedPackage(name: "firefox", kind: .cask, installedVersions: ["1"], currentVersion: "2")

    func testCommandsAreFixedFormsForKnownPackagesOnly() {
        XCTAssertEqual(UpdateActions.action(for: wget, among: [wget, firefox]), .copyUpgradeCommand("brew upgrade wget"))
        XCTAssertEqual(UpdateActions.action(for: firefox, among: [wget, firefox]), .copyUpgradeCommand("brew upgrade --cask firefox"))
        XCTAssertNil(UpdateActions.action(for: wget, among: [firefox]))
    }

    func testMaliciousOrMalformedNamesGetNoAction() {
        for name in ["-f", "a b", "a;rm -rf ~", "$(whoami)", "a`b`", "x\ny", "", "名前"] {
            let package = OutdatedPackage(name: name, kind: .formula, installedVersions: [], currentVersion: "1")
            XCTAssertNil(UpdateActions.action(for: package, among: [package]), name)
        }
        for name in ["python@3.12", "homebrew/cask/foo", "gcc-13", "c++filt", "node_exporter"] {
            XCTAssertTrue(UpdateActions.isValidPackageName(name), name)
        }
    }
}
