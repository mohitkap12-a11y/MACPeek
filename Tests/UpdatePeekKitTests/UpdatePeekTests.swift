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

private struct FixedNpmLocator: NpmLocating {
    let path: String?
    func npmPath() -> String? { path }
}

private struct FixedRecord: SoftwareUpdateRecordReading {
    let report: MacOSUpdateReport?
    func read() -> MacOSUpdateReport? { report }
}

private struct FixedMacOSChecker: MacOSUpdateChecking {
    let result: Result<[MacOSUpdate], Error>
    func list() async throws -> [MacOSUpdate] { try result.get() }
}

private final class RecordingInstaller: NpmInstalling, @unchecked Sendable {
    private let lock = NSLock()
    private var _names: [String] = []
    let error: Error?
    init(error: Error? = nil) { self.error = error }
    var names: [String] { lock.lock(); defer { lock.unlock() }; return _names }
    func install(_ name: String) async throws {
        lock.lock(); _names.append(name); lock.unlock()
        if let error { throw error }
    }
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

private let npmSample = """
{"typescript":{"current":"5.4.5","wanted":"5.4.5","latest":"5.6.2","dependent":"global","location":"/opt/homebrew/lib/node_modules/typescript"},
 "@angular/cli":{"current":"17.0.0","wanted":"17.0.0","latest":"18.2.1","dependent":"global","location":"/x"},
 "npm":{"current":"10.2.0","wanted":"10.2.0","latest":"10.8.3","dependent":"global","location":"/y"}}
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
    private func make(brewPath: String? = nil, npmPath: String? = nil, runner: CommandRunning,
                      installer: NpmInstalling = RecordingInstaller(),
                      record: MacOSUpdateReport? = nil,
                      macOS: Result<[MacOSUpdate], Error> = .success([])) -> UpdateStatusService {
        let brewLocator = FixedLocator(path: brewPath)
        let npmLocator = FixedNpmLocator(path: npmPath)
        return UpdateStatusService(os: FixedOS(), locator: brewLocator,
                                   homebrew: BrewOutdatedChecker(runner: runner, locator: brewLocator),
                                   npmLocator: npmLocator, npm: NpmOutdatedChecker(runner: runner, locator: npmLocator),
                                   npmInstaller: installer,
                                   macOSRecord: FixedRecord(report: record), macOSChecker: FixedMacOSChecker(result: macOS))
    }

    private func service(path: String?, runner: CommandRunning) -> UpdateStatusService {
        make(brewPath: path, runner: runner)
    }

    private func npmService(path: String?, runner: CommandRunning) -> UpdateStatusService {
        make(npmPath: path, runner: runner)
    }

    func testMacOSIsNotCheckedWithoutARecordOrACheck() {
        let runner = ScriptedRunner(ok(""))
        XCTAssertEqual(make(runner: runner).initialMacOSState(), .notChecked)
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testMacOSStartsFromMacOSsOwnRecordWhenItListsAnUpdate() {
        let report = MacOSUpdateReport(updates: [MacOSUpdate(name: "macOS Sequoia 15.1", version: "15.1")],
                                       source: .macOSRecord, checkedAt: nil)
        XCTAssertEqual(make(runner: ScriptedRunner(ok("")), record: report).initialMacOSState(), .known(report))
    }

    func testCheckNowReportsWhatSoftwareUpdateListed() async {
        let update = MacOSUpdate(name: "macOS Sequoia 15.1", version: "15.1", isRecommended: true, requiresRestart: true)
        let state = await make(runner: ScriptedRunner(ok("")), macOS: .success([update])).checkMacOS()
        guard case .known(let report) = state else { return XCTFail("expected known, got \(state)") }
        XCTAssertEqual(report.updates, [update])
        XCTAssertEqual(report.source, .softwareUpdateTool)
        XCTAssertNotNil(report.checkedAt)
    }

    func testCheckNowWithNothingListedIsAnEmptyReportNotAFailure() async {
        let state = await make(runner: ScriptedRunner(ok("")), macOS: .success([])).checkMacOS()
        guard case .known(let report) = state else { return XCTFail("expected known, got \(state)") }
        XCTAssertTrue(report.updates.isEmpty)
    }

    func testCheckNowFailuresAreShownAsFailuresWithAMessage() async {
        let state = await make(runner: ScriptedRunner(ok("")),
                               macOS: .failure(UpdatePeekError.operationFailed(SoftwareUpdateChecker.failureMessage))).checkMacOS()
        XCTAssertEqual(state, .failed(message: SoftwareUpdateChecker.failureMessage))
    }

    func testUpdatingAnNpmPackageRunsTheInstallerOnlyForListedValidPackages() async {
        let installer = RecordingInstaller()
        let listed = OutdatedPackage(name: "typescript", kind: .npm, installedVersions: ["5.4.5"], currentVersion: "5.6.2")
        let service = make(npmPath: "/opt/homebrew/bin/npm", runner: ScriptedRunner(ok("")), installer: installer)
        let installed = await service.updateNpmPackage(listed, among: [listed])
        XCTAssertEqual(installed, .installed)
        XCTAssertEqual(installer.names, ["typescript"])

        let notListed = await service.updateNpmPackage(listed, among: [])
        let brew = OutdatedPackage(name: "wget", kind: .formula, installedVersions: ["1"], currentVersion: "2")
        let wrongKind = await service.updateNpmPackage(brew, among: [brew])
        let evil = OutdatedPackage(name: "-g", kind: .npm, installedVersions: [], currentVersion: "1")
        let badName = await service.updateNpmPackage(evil, among: [evil])
        for outcome in [notListed, wrongKind, badName] {
            XCTAssertEqual(outcome, .failed(message: "MacPeek can't update that package."))
        }
        XCTAssertEqual(installer.names, ["typescript"], "refused updates must not reach the installer")
    }

    func testAnInstallerFailureIsReportedWithItsSafeMessage() async {
        let installer = RecordingInstaller(error: UpdatePeekError.operationFailed(NpmGlobalInstaller.permissionMessage))
        let listed = OutdatedPackage(name: "typescript", kind: .npm, installedVersions: ["5.4.5"], currentVersion: "5.6.2")
        let outcome = await make(runner: ScriptedRunner(ok("")), installer: installer).updateNpmPackage(listed, among: [listed])
        XCTAssertEqual(outcome, .failed(message: NpmGlobalInstaller.permissionMessage))
    }

    func testNpmInitialStateDependsOnlyOnWhetherNpmWasFound() {
        let runner = ScriptedRunner(ok(npmSample))
        XCTAssertEqual(npmService(path: nil, runner: runner).initialNpmState(), .notInstalled)
        XCTAssertEqual(npmService(path: "/opt/homebrew/bin/npm", runner: runner).initialNpmState(), .notChecked)
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testNpmCheckedStateCarriesPackages() async {
        let runner = ScriptedRunner(.success(CommandOutput(stdout: npmSample, stderr: "", status: 1)))
        let state = await npmService(path: "/opt/homebrew/bin/npm", runner: runner).checkNpm()
        guard case .checked(let report) = state else { return XCTFail("expected checked, got \(state)") }
        XCTAssertEqual(report.packages.map(\.name), ["@angular/cli", "npm", "typescript"])
    }

    func testNpmAbsentIsNotAnErrorAndRunsNothing() async {
        let runner = ScriptedRunner(ok(npmSample))
        let state = await npmService(path: nil, runner: runner).checkNpm()
        XCTAssertEqual(state, .notInstalled)
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testNpmFailureIsRetryable() async {
        let runner = ScriptedRunner(.success(CommandOutput(stdout: "garbage", stderr: "", status: 1)))
        let state = await npmService(path: "/usr/local/bin/npm", runner: runner).checkNpm()
        XCTAssertEqual(state, .failed(message: "npm's answer could not be understood.", retryable: true))
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

final class NpmParserTests: XCTestCase {
    func testParsesPackagesSortedByNameWithLatestAsTarget() throws {
        let packages = try NpmParser.parse(npmSample)
        XCTAssertEqual(packages.map(\.name), ["@angular/cli", "npm", "typescript"])
        let ts = try XCTUnwrap(packages.last)
        XCTAssertEqual(ts.kind, .npm)
        XCTAssertEqual(ts.installedVersions, ["5.4.5"])
        XCTAssertEqual(ts.currentVersion, "5.6.2")
        XCTAssertEqual(ts.id, "npm:typescript")
    }

    func testEmptyObjectIsNoOutdatedPackages() throws {
        XCTAssertEqual(try NpmParser.parse("{}"), [])
    }

    func testMissingCurrentIsNotReportedRatherThanInvented() throws {
        let packages = try NpmParser.parse(#"{"left-pad":{"wanted":"1.0.0","latest":"1.3.0"}}"#)
        XCTAssertEqual(packages.first?.installedVersions, [])
        XCTAssertEqual(packages.first?.installedLabel, "Not reported")
    }

    func testAnArrayEntryUsesItsFirstLocation() throws {
        let packages = try NpmParser.parse(#"{"a":[{"current":"1.0.0","latest":"2.0.0"},{"current":"1.1.0","latest":"2.0.0"}]}"#)
        XCTAssertEqual(packages.map(\.name), ["a"])
        XCTAssertEqual(packages.first?.installedVersions, ["1.0.0"])
    }

    func testNpmsOwnErrorObjectIsAFailureNotAPackage() {
        let error = #"{"error":{"code":"ENOTFOUND","summary":"request to https://registry.npmjs.org/x failed","detail":"getaddrinfo"}}"#
        XCTAssertThrowsError(try NpmParser.parse(error)) {
            XCTAssertEqual($0 as? UpdatePeekError, .operationFailed(NpmParser.failureMessage))
        }
    }

    func testARealPackageNamedErrorIsStillAPackage() throws {
        let packages = try NpmParser.parse(#"{"error":{"current":"1.0.0","wanted":"1.0.0","latest":"1.1.0"}}"#)
        XCTAssertEqual(packages.map(\.name), ["error"])
    }

    func testMalformedShapesFail() {
        for bad in ["", "not json", "[]", #"{"x":"nope"}"#, #"{"x":{"current":"1"}}"#, #"{"x":{"latest":""}}"#, #"{"x":{"latest":5}}"#] {
            XCTAssertThrowsError(try NpmParser.parse(bad), bad) { XCTAssertEqual($0 as? UpdatePeekError, .malformedData) }
        }
    }

    func testChattyOutputIsNotParsedAsData() {
        XCTAssertThrowsError(try NpmParser.parse("npm warn something\n" + npmSample))
    }
}

final class NpmCheckerTests: XCTestCase {
    func testUsesFixedExecutableArgumentsAndNpmsOwnDirectoryOnPath() async throws {
        let runner = ScriptedRunner(.success(CommandOutput(stdout: npmSample, stderr: "", status: 1)))
        let checker = NpmOutdatedChecker(runner: runner, locator: FixedNpmLocator(path: "/opt/homebrew/bin/npm"))
        let report = try await checker.outdated()
        XCTAssertEqual(report.packages.count, 3)
        let call = try XCTUnwrap(runner.calls.first)
        XCTAssertEqual(call.0, "/usr/bin/env")
        XCTAssertEqual(call.1, ["PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin", "npm_config_update_notifier=false",
                                "npm_config_fund=false", "/opt/homebrew/bin/npm", "outdated", "--global", "--json"])
    }

    func testExitZeroWithNoOutputMeansNothingOutdated() async throws {
        let checker = NpmOutdatedChecker(runner: ScriptedRunner(ok("")), locator: FixedNpmLocator(path: "/usr/local/bin/npm"))
        let report = try await checker.outdated()
        XCTAssertTrue(report.packages.isEmpty)
    }

    func testExitOneWithNoOutputIsAFailureNotNothingOutdated() async {
        let runner = ScriptedRunner(.success(CommandOutput(stdout: "", stderr: "npm ERR! /Users/me/secret", status: 1)))
        let checker = NpmOutdatedChecker(runner: runner, locator: FixedNpmLocator(path: "/usr/local/bin/npm"))
        do { _ = try await checker.outdated(); XCTFail("expected error") } catch {
            XCTAssertEqual(error as? UpdatePeekError, .operationFailed(NpmParser.failureMessage))
            XCTAssertFalse(error.localizedDescription.contains("secret"))
        }
    }

    func testOtherExitCodesFail() async {
        let runner = ScriptedRunner(.success(CommandOutput(stdout: npmSample, stderr: "", status: 127)))
        let checker = NpmOutdatedChecker(runner: runner, locator: FixedNpmLocator(path: "/usr/local/bin/npm"))
        do { _ = try await checker.outdated(); XCTFail("expected error") } catch {
            XCTAssertEqual(error as? UpdatePeekError, .operationFailed(NpmParser.failureMessage))
        }
    }

    func testMissingNpmIsSourceUnavailableAndRunsNothing() async {
        let runner = ScriptedRunner(ok(npmSample))
        let checker = NpmOutdatedChecker(runner: runner, locator: FixedNpmLocator(path: nil))
        do { _ = try await checker.outdated(); XCTFail("expected error") } catch {
            guard case UpdatePeekError.sourceUnavailable = error else { return XCTFail("wrong error \(error)") }
        }
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testTimeoutIsReportedNotRaw() async {
        let runner = ScriptedRunner(.failure(CommandError.timedOut("npm")))
        let checker = NpmOutdatedChecker(runner: runner, locator: FixedNpmLocator(path: "/usr/local/bin/npm"))
        do { _ = try await checker.outdated(); XCTFail("expected error") } catch {
            guard case UpdatePeekError.operationFailed = error else { return XCTFail("wrong error \(error)") }
        }
    }
}

final class NpmUpdateActionTests: XCTestCase {
    private func package(_ name: String) -> OutdatedPackage {
        OutdatedPackage(name: name, kind: .npm, installedVersions: ["1.0.0"], currentVersion: "2.0.0")
    }

    func testCommandIsAFixedFormForKnownPackagesOnly() {
        let ts = package("typescript"), scoped = package("@angular/cli")
        XCTAssertEqual(UpdateActions.action(for: ts, among: [ts, scoped]), .copyUpgradeCommand("npm install -g typescript@latest"))
        XCTAssertEqual(UpdateActions.action(for: scoped, among: [ts, scoped]), .copyUpgradeCommand("npm install -g @angular/cli@latest"))
        XCTAssertNil(UpdateActions.action(for: ts, among: [scoped]))
    }

    func testMaliciousOrMalformedNamesGetNoAction() {
        for name in ["-g", "--prefix=/x", "a b", "a;rm -rf ~", "$(whoami)", "a`b`", "x\ny", "", "名前", "@", "@scope", "@/x",
                     "@scope/", "@a/b/c", ".hidden", "_private", "Upper", "a@latest", String(repeating: "a", count: 215)] {
            let p = package(name)
            XCTAssertNil(UpdateActions.action(for: p, among: [p]), name)
        }
        for name in ["lodash", "left-pad", "@types/node", "@angular/cli", "a.b_c~d", "node-gyp"] {
            XCTAssertTrue(UpdateActions.isValidNpmPackageName(name), name)
        }
    }
}

final class SoftwareUpdateListParserTests: XCTestCase {
    private let listed = """
    Software Update Tool

    Finding available software
    Software Update found the following new or updated software:
    * Label: macOS Sequoia 15.1-24B83
    \tTitle: macOS Sequoia 15.1, Version: 15.1, Size: 3000000KiB, Recommended: YES, Action: restart,
    * Label: Safari18.1SequoiaAuto-18.1
    \tTitle: Safari, Version: 18.1, Size: 150000KiB, Recommended: YES,
    """

    func testParsesUpdatesWithTheirDetails() throws {
        let updates = try SoftwareUpdateListParser.parse(listed)
        XCTAssertEqual(updates.map(\.name), ["macOS Sequoia 15.1", "Safari"])
        XCTAssertEqual(updates[0].version, "15.1")
        XCTAssertEqual(updates[0].isRecommended, true)
        XCTAssertEqual(updates[0].requiresRestart, true)
        XCTAssertNil(updates[1].requiresRestart, "no Action field means not reported")
    }

    func testNoNewSoftwareIsAnEmptyList() throws {
        XCTAssertEqual(try SoftwareUpdateListParser.parse("Software Update Tool\n\nFinding available software\nNo new software available.\n"), [])
    }

    func testATitleWithACommaIsKeptWhole() throws {
        let text = "* Label: X-1\n\tTitle: Foo, Bar Update, Version: 2.0, Size: 1KiB, Recommended: NO,\n"
        let update = try XCTUnwrap(SoftwareUpdateListParser.parse(text).first)
        XCTAssertEqual(update.name, "Foo, Bar Update")
        XCTAssertEqual(update.version, "2.0")
        XCTAssertEqual(update.isRecommended, false)
    }

    func testAnUpdateWithoutDetailsFallsBackToItsLabel() throws {
        let updates = try SoftwareUpdateListParser.parse("* Label: Lonely-1.0\n")
        XCTAssertEqual(updates.map(\.name), ["Lonely-1.0"])
    }

    func testAnythingElseIsMalformedNeverNothingToDo() {
        for bad in ["", "Software Update Tool\n\nFinding available software\n", "softwareupdate: Can't connect to the server",
                    "Software Update found the following new or updated software:"] {
            XCTAssertThrowsError(try SoftwareUpdateListParser.parse(bad), bad) { XCTAssertEqual($0 as? UpdatePeekError, .malformedData) }
        }
    }
}

final class SoftwareUpdateCheckerTests: XCTestCase {
    func testRunsAFixedExecutableAndArgument() async throws {
        let runner = ScriptedRunner(.success(CommandOutput(stdout: "* Label: A-1\n\tTitle: A, Version: 1, Size: 1KiB,\n", stderr: "Finding available software\n", status: 0)))
        let updates = try await SoftwareUpdateChecker(runner: runner).list()
        XCTAssertEqual(updates.map(\.name), ["A"])
        let call = try XCTUnwrap(runner.calls.first)
        XCTAssertEqual(call.0, "/usr/sbin/softwareupdate")
        XCTAssertEqual(call.1, ["--list"])
    }

    func testTheListIsReadFromStderrToo() async throws {
        let runner = ScriptedRunner(.success(CommandOutput(stdout: "", stderr: "No new software available.\n", status: 0)))
        let updates = try await SoftwareUpdateChecker(runner: runner).list()
        XCTAssertTrue(updates.isEmpty)
    }

    func testNonZeroExitDoesNotLeakRawOutput() async {
        let runner = ScriptedRunner(.success(CommandOutput(stdout: "", stderr: "error at /Users/me/secret", status: 1)))
        do { _ = try await SoftwareUpdateChecker(runner: runner).list(); XCTFail("expected error") } catch {
            XCTAssertEqual(error as? UpdatePeekError, .operationFailed(SoftwareUpdateChecker.failureMessage))
            XCTAssertFalse(error.localizedDescription.contains("secret"))
        }
    }

    func testUnrecognisedOutputIsAFailureNotNothingToDo() async {
        let runner = ScriptedRunner(ok("something unexpected"))
        do { _ = try await SoftwareUpdateChecker(runner: runner).list(); XCTFail("expected error") } catch {
            XCTAssertEqual(error as? UpdatePeekError, .operationFailed("macOS's answer could not be understood."))
        }
    }

    func testTimeoutIsReportedNotRaw() async {
        let runner = ScriptedRunner(.failure(CommandError.timedOut("softwareupdate")))
        do { _ = try await SoftwareUpdateChecker(runner: runner).list(); XCTFail("expected error") } catch {
            guard case UpdatePeekError.operationFailed = error else { return XCTFail("wrong error \(error)") }
        }
    }
}

final class SoftwareUpdateRecordTests: XCTestCase {
    private func write(_ object: Any, name: String = UUID().uuidString) throws -> String {
        let path = NSTemporaryDirectory() + "updatepeek-\(name).plist"
        let data = try PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: path))
        addTeardownBlock { try? FileManager.default.removeItem(atPath: path) }
        return path
    }

    func testReadsUpdatesMacOSRecordedAndWhenItLastSucceeded() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let record: [String: Any] = [
            "RecommendedUpdates": [["Display Name": "macOS Sequoia 15.1", "Display Version": "15.1", "Identifier": "MSU_UPDATE_24B83"]],
            "LastFullSuccessfulDate": date,
        ]
        let path = try write(record)
        let report = try XCTUnwrap(PreferencesSoftwareUpdateRecord(path: path).read())
        XCTAssertEqual(report.updates, [MacOSUpdate(name: "macOS Sequoia 15.1", version: "15.1")])
        XCTAssertEqual(report.source, .macOSRecord)
        XCTAssertEqual(report.checkedAt, date)
    }

    func testAnEmptyOrMissingRecordProvesNothingSoItIsNil() throws {
        XCTAssertNil(PreferencesSoftwareUpdateRecord(path: try write(["RecommendedUpdates": [[String: Any]]()])).read())
        XCTAssertNil(PreferencesSoftwareUpdateRecord(path: try write(["LastUpdatesAvailable": 0])).read())
        XCTAssertNil(PreferencesSoftwareUpdateRecord(path: "/nonexistent/com.apple.SoftwareUpdate.plist").read())
    }

    func testWrongTypesAndGarbageAreIgnored() throws {
        XCTAssertNil(PreferencesSoftwareUpdateRecord(path: try write(["RecommendedUpdates": "nope"])).read())
        XCTAssertNil(PreferencesSoftwareUpdateRecord(path: try write(["RecommendedUpdates": [["Display Name": 5]]])).read())
        let path = NSTemporaryDirectory() + "updatepeek-garbage-\(UUID().uuidString).plist"
        try Data("not a plist".utf8).write(to: URL(fileURLWithPath: path))
        addTeardownBlock { try? FileManager.default.removeItem(atPath: path) }
        XCTAssertNil(PreferencesSoftwareUpdateRecord(path: path).read())
    }

    func testAnOversizedFileIsRejectedWithoutBeingParsed() throws {
        let path = NSTemporaryDirectory() + "updatepeek-big-\(UUID().uuidString).plist"
        try Data(repeating: 0x20, count: 2_100_000).write(to: URL(fileURLWithPath: path))
        addTeardownBlock { try? FileManager.default.removeItem(atPath: path) }
        XCTAssertNil(PreferencesSoftwareUpdateRecord(path: path).read())
    }
}

final class NpmInstallerTests: XCTestCase {
    func testUsesFixedExecutableAndArgumentsWithNpmsDirectoryOnPath() async throws {
        let runner = ScriptedRunner(ok(""))
        try await NpmGlobalInstaller(runner: runner, locator: FixedNpmLocator(path: "/opt/homebrew/bin/npm")).install("@angular/cli")
        let call = try XCTUnwrap(runner.calls.first)
        XCTAssertEqual(call.0, "/usr/bin/env")
        XCTAssertEqual(call.1, ["PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin", "npm_config_update_notifier=false",
                                "npm_config_fund=false", "/opt/homebrew/bin/npm", "install", "--global", "--no-audit", "--no-fund",
                                "@angular/cli@latest"])
    }

    func testInvalidNamesNeverRunAnything() async {
        let runner = ScriptedRunner(ok(""))
        let installer = NpmGlobalInstaller(runner: runner, locator: FixedNpmLocator(path: "/usr/local/bin/npm"))
        for name in ["-g", "--prefix=/x", "a b", "a;rm -rf ~", "$(whoami)", "", "Upper", "a@latest"] {
            do { try await installer.install(name); XCTFail("expected error for \(name)") } catch {
                XCTAssertEqual(error as? UpdatePeekError, .operationFailed("MacPeek can't update a package with that name."), name)
            }
        }
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testMissingNpmIsSourceUnavailableAndRunsNothing() async {
        let runner = ScriptedRunner(ok(""))
        do {
            try await NpmGlobalInstaller(runner: runner, locator: FixedNpmLocator(path: nil)).install("typescript")
            XCTFail("expected error")
        } catch {
            guard case UpdatePeekError.sourceUnavailable = error else { return XCTFail("wrong error \(error)") }
        }
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testPermissionFailuresGetTheFixedExplanationAndNeverRawOutput() async {
        for text in ["npm ERR! code EACCES\nnpm ERR! path /usr/local/lib/node_modules/secret", "Error: EPERM: operation not permitted", "permission denied"] {
            let runner = ScriptedRunner(.success(CommandOutput(stdout: "", stderr: text, status: 243)))
            do {
                try await NpmGlobalInstaller(runner: runner, locator: FixedNpmLocator(path: "/usr/local/bin/npm")).install("typescript")
                XCTFail("expected error")
            } catch {
                XCTAssertEqual(error as? UpdatePeekError, .operationFailed(NpmGlobalInstaller.permissionMessage))
                XCTAssertFalse(error.localizedDescription.contains("secret"))
            }
        }
    }

    func testOtherFailuresNameThePackageOnly() async {
        let runner = ScriptedRunner(.success(CommandOutput(stdout: "", stderr: "npm ERR! 404 /Users/me/private", status: 1)))
        do {
            try await NpmGlobalInstaller(runner: runner, locator: FixedNpmLocator(path: "/usr/local/bin/npm")).install("typescript")
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? UpdatePeekError, .operationFailed("npm could not update typescript."))
            XCTAssertFalse(error.localizedDescription.contains("private"))
        }
    }

    func testOnlyListedValidNpmPackagesCanBeUpdatedInMacPeek() {
        let ts = OutdatedPackage(name: "typescript", kind: .npm, installedVersions: ["1"], currentVersion: "2")
        let wget = OutdatedPackage(name: "wget", kind: .formula, installedVersions: ["1"], currentVersion: "2")
        XCTAssertTrue(UpdateActions.canUpdateInMacPeek(ts, among: [ts]))
        XCTAssertFalse(UpdateActions.canUpdateInMacPeek(ts, among: []))
        XCTAssertFalse(UpdateActions.canUpdateInMacPeek(wget, among: [wget]), "Homebrew stays copy-only")
    }
}
