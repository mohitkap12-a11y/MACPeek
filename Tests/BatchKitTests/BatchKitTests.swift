import XCTest
@testable import BatchKit
import MacPeekCore

// MARK: - Fakes

/// Answers each command by the first rule whose words all appear in it; records every call.
private final class RuleRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [[String]] = []
    private let rules: [([String], CommandOutput)]
    private let fallback: CommandOutput

    init(_ rules: [([String], CommandOutput)], fallback: CommandOutput = CommandOutput(stdout: "", stderr: "", status: 1)) {
        self.rules = rules
        self.fallback = fallback
    }

    var calls: [[String]] { lock.lock(); defer { lock.unlock() }; return _calls }

    func run(_ executable: String, _ arguments: [String]) async throws -> CommandOutput {
        let line = [executable] + arguments
        lock.lock(); _calls.append(line); lock.unlock()
        for (words, output) in rules where words.allSatisfy(line.contains) { return output }
        return fallback
    }
}

private final class FakeOllama: OllamaControlling, @unchecked Sendable {
    var running: Bool
    var models: Set<String>
    var pullError: Error?
    private(set) var pulled: [String] = []

    init(running: Bool = true, models: Set<String> = [], pullError: Error? = nil) {
        self.running = running
        self.models = models
        self.pullError = pullError
    }

    func isRunning() async -> Bool { running }
    func installedModels() async throws -> Set<String> { models }
    func pull(_ model: String, progress: @escaping @Sendable (Double?, String) async -> Void) async throws {
        pulled.append(model)
        await progress(0.5, "pulling abc")
        if let pullError { throw pullError }
        await progress(1, "success")
    }
}

private let ok = CommandOutput(stdout: "", stderr: "", status: 0)
private let gb: UInt64 = 1_000_000_000

private func environment(brew: Bool = true, docker: Bool = true, memory: UInt64 = 64 * gb, disk: UInt64? = 400 * gb) -> BatchEnvironment {
    BatchEnvironment(brew: ExecutableLocator(candidates: ["/opt/homebrew/bin/brew"], isExecutable: { _ in brew }),
                     docker: ExecutableLocator(candidates: ["/usr/local/bin/docker"], isExecutable: { _ in docker }),
                     podman: ExecutableLocator(candidates: ["/opt/podman/bin/podman"], isExecutable: { _ in false }),
                     memoryBytes: { memory }, freeDiskBytes: { disk })
}

private func installer(_ runner: RuleRunner, ollama: FakeOllama = FakeOllama(), env: BatchEnvironment = environment()) -> SystemBatchInstaller {
    SystemBatchInstaller(environment: env, quick: runner, long: runner, ollama: ollama, sleep: { _ in })
}

// MARK: - Validation

final class BatchValidationTests: XCTestCase {
    func testNamesThatCanNeverBecomeOptions() {
        XCTAssertNil(BatchValidation.problem(with: BatchItem(kind: .brewFormula, name: "ollama")))
        XCTAssertNil(BatchValidation.problem(with: BatchItem(kind: .brewFormula, name: "python@3.13")))
        XCTAssertNil(BatchValidation.problem(with: BatchItem(kind: .brewCask, name: "homebrew/cask/visual-studio-code")))
        XCTAssertNil(BatchValidation.problem(with: BatchItem(kind: .ollamaModel, name: "llama3.3:70b")))
        XCTAssertNil(BatchValidation.problem(with: BatchItem(kind: .ollamaModel, name: "hf.co/bartowski/Llama-3.2-1B-Instruct-GGUF:Q4_K_M")))
        XCTAssertNil(BatchValidation.problem(with: BatchItem(kind: .containerImage, name: "ghcr.io/team/app:1.2")))
        for bad in ["--force", "-x", "a b", "a;rm", "a$(x)", "", "../x", "a\nb"] {
            for kind in BatchItem.Kind.allCases {
                XCTAssertNotNil(BatchValidation.problem(with: BatchItem(kind: kind, name: bad)), "\(kind) \(bad)")
            }
        }
    }

    func testOnlyFormulaeStartServices() {
        XCTAssertNil(BatchValidation.problem(with: BatchItem(kind: .brewFormula, name: "ollama", startService: true)))
        XCTAssertNotNil(BatchValidation.problem(with: BatchItem(kind: .brewCask, name: "docker", startService: true)))
    }

    func testPlanRules() {
        let item = BatchItem(kind: .brewFormula, name: "uv")
        XCTAssertNil(BatchValidation.problem(with: BatchPlan(id: "A1-b2", name: "Dev box", items: [item])))
        XCTAssertNotNil(BatchValidation.problem(with: BatchPlan(id: "bad id", name: "Dev box", items: [item])))
        XCTAssertNotNil(BatchValidation.problem(with: BatchPlan(name: " ", items: [item])))
        XCTAssertNotNil(BatchValidation.problem(with: BatchPlan(name: "Two\nlines", items: [item])))
        XCTAssertNotNil(BatchValidation.problem(with: BatchPlan(name: "Empty", items: [])))
        XCTAssertNotNil(BatchValidation.problem(with: BatchPlan(name: "Twice", items: [item, item])))
        let many = (0...BatchValidation.maximumItems).map { BatchItem(kind: .brewFormula, name: "p\($0)") }
        XCTAssertNotNil(BatchValidation.problem(with: BatchPlan(name: "Many", items: many)))
    }

    func testValuesRoundTrip() throws {
        let plan = BatchPlan(id: "x1", name: "AI Dev Box", items: [
            BatchItem(kind: .ollamaModel, name: "llama3.3:70b", requirements: BatchRequirements(memoryBytes: 48 * gb, diskBytes: 43 * gb))])
        XCTAssertEqual(try JSONDecoder().decode(BatchPlan.self, from: try JSONEncoder().encode(plan)), plan)
        let status = BatchStatus(plan: plan, startedBy: "Studio MacBook", createdAt: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(try JSONDecoder().decode(BatchStatus.self, from: try JSONEncoder().encode(status)), status)
    }
}

// MARK: - Installer

final class BatchInstallerTests: XCTestCase {
    func testCheckFindsWhatIsInstalledReadyOrBlocked() async {
        let runner = RuleRunner([
            (["list", "--formula", "uv"], CommandOutput(stdout: "uv 0.9.1\n", stderr: "", status: 0)),
            (["image", "inspect", "postgres:17"], ok),
        ])
        let ollama = FakeOllama(models: ["qwen3:32b"])
        let checks = await installer(runner, ollama: ollama, env: environment(memory: 24 * gb)).check([
            BatchItem(kind: .brewFormula, name: "uv"),
            BatchItem(kind: .brewFormula, name: "git"),
            BatchItem(kind: .ollamaModel, name: "qwen3:32b"),
            BatchItem(kind: .ollamaModel, name: "llama3.3:70b", requirements: BatchRequirements(memoryBytes: 48 * gb)),
            BatchItem(kind: .containerImage, name: "postgres:17"),
            BatchItem(kind: .containerImage, name: "redis:8"),
        ])
        XCTAssertEqual(checks.map(\.verdict), [.installed, .ready, .installed, .blocked, .installed, .ready])
        XCTAssertEqual(checks[3].reason, "Needs 48 GB of memory; this Mac has 24 GB.")
    }

    func testMissingToolsBlock() async {
        let checks = await installer(RuleRunner([]), ollama: FakeOllama(running: false), env: environment(brew: false, docker: false)).check([
            BatchItem(kind: .brewCask, name: "orbstack"),
            BatchItem(kind: .ollamaModel, name: "llama3.1:8b"),
            BatchItem(kind: .containerImage, name: "redis:8"),
        ])
        XCTAssertEqual(checks.map(\.verdict), [.blocked, .blocked, .blocked])
        XCTAssertEqual(checks[0].reason, "Homebrew isn't installed on this Mac.")
    }

    func testOllamaStartedEarlierInTheBatchCounts() async {
        let checks = await installer(RuleRunner([]), ollama: FakeOllama(running: false)).check([
            BatchItem(kind: .brewFormula, name: "ollama", startService: true),
            BatchItem(kind: .ollamaModel, name: "llama3.1:8b"),
        ])
        XCTAssertEqual(checks.map(\.verdict), [.ready, .ready])
    }

    func testDiskIsCountedAcrossItemsWithAMargin() async {
        let big = BatchRequirements(diskBytes: 40 * gb)
        let checks = await installer(RuleRunner([]), env: environment(disk: 90 * gb)).check([
            BatchItem(kind: .ollamaModel, name: "a:1", requirements: big),
            BatchItem(kind: .ollamaModel, name: "b:1", requirements: big),
        ])
        // 90 − 40 leaves 50; the second needs 40 + 5 margin = 45: fits. A third would not.
        XCTAssertEqual(checks.map(\.verdict), [.ready, .ready])
        let three = await installer(RuleRunner([]), env: environment(disk: 90 * gb)).check([
            BatchItem(kind: .ollamaModel, name: "a:1", requirements: big),
            BatchItem(kind: .ollamaModel, name: "b:1", requirements: big),
            BatchItem(kind: .ollamaModel, name: "c:1", requirements: big),
        ])
        XCTAssertEqual(three.last?.verdict, .blocked)
    }

    func testBrewRunsDirectlyWithoutAutoUpdateAndStartsTheService() async {
        let runner = RuleRunner([(["install"], ok), (["services", "start"], ok)])
        let result = await installer(runner).install(BatchItem(kind: .brewFormula, name: "ollama", startService: true)) { _, _ in }
        XCTAssertEqual(result, .done)
        XCTAssertEqual(runner.calls[0], ["/usr/bin/env", "HOMEBREW_NO_AUTO_UPDATE=1", "HOMEBREW_NO_ANALYTICS=1", "HOMEBREW_NO_ENV_HINTS=1",
                                         "HOMEBREW_NO_INSTALL_CLEANUP=1", "/opt/homebrew/bin/brew", "install", "--formula", "ollama"])
        XCTAssertEqual(runner.calls[1].suffix(3), ["services", "start", "ollama"])
        XCTAssertFalse(runner.calls.joined().contains("sudo"))
    }

    func testBrewFailuresGetPlainMessages() async {
        let sudo = RuleRunner([(["install"], CommandOutput(stdout: "", stderr: "sudo: a password is required", status: 1))])
        let result = await installer(sudo).install(BatchItem(kind: .brewCask, name: "some-driver")) { _, _ in }
        XCTAssertEqual(result, .failed("some-driver needs an administrator password to install. Batches never use one."))
        let missing = RuleRunner([(["install"], CommandOutput(stdout: "", stderr: "Error: No available formula with the name \"nope\".", status: 1))])
        let second = await installer(missing).install(BatchItem(kind: .brewFormula, name: "nope")) { _, _ in }
        XCTAssertEqual(second, .failed("Homebrew has no package named nope."))
    }

    func testModelPullReportsProgress() async {
        let ollama = FakeOllama()
        let seen = Seen()
        let result = await installer(RuleRunner([]), ollama: ollama).install(BatchItem(kind: .ollamaModel, name: "llama3.1:8b")) { fraction, detail in
            await seen.add(fraction, detail)
        }
        XCTAssertEqual(result, .done)
        XCTAssertEqual(ollama.pulled, ["llama3.1:8b"])
        let lines = await seen.lines
        XCTAssertEqual(lines.first?.1, "Downloading 50%")
        XCTAssertEqual(lines.last?.1, "Done")
    }

    func testModelPullFailsWhenOllamaNeverAnswers() async {
        let result = await installer(RuleRunner([]), ollama: FakeOllama(running: false)).install(BatchItem(kind: .ollamaModel, name: "a:1")) { _, _ in }
        XCTAssertEqual(result, .failed("Ollama isn't running on this Mac."))
    }

    func testImagePullUsesTheEngineDirectly() async {
        let runner = RuleRunner([(["pull"], ok)])
        let result = await installer(runner).install(BatchItem(kind: .containerImage, name: "redis:8")) { _, _ in }
        XCTAssertEqual(result, .done)
        XCTAssertEqual(runner.calls.last, ["/usr/local/bin/docker", "pull", "redis:8"])
    }

    func testInvalidItemsNeverRun() async {
        let runner = RuleRunner([], fallback: ok)
        let result = await installer(runner).install(BatchItem(kind: .brewFormula, name: "--HEAD")) { _, _ in }
        if case .done = result { XCTFail("must refuse") }
        XCTAssertTrue(runner.calls.isEmpty)
    }
}

private actor Seen {
    var lines: [(Double?, String?)] = []
    func add(_ fraction: Double?, _ detail: String?) { lines.append((fraction, detail)) }
}

// MARK: - Ollama parsing

final class OllamaParsingTests: XCTestCase {
    func testTagsAndNames() {
        let data = Data(#"{"models":[{"name":"llama3.3:70b"},{"name":"qwen3"}]}"#.utf8)
        XCTAssertEqual(OllamaNames.parseTags(data), ["llama3.3:70b", "qwen3:latest"])
        XCTAssertEqual(OllamaNames.normalized("hf.co/owner/repo"), "hf.co/owner/repo:latest")
        XCTAssertNil(OllamaNames.parseTags(Data("nope".utf8)))
    }

    func testPullLines() {
        let line = OllamaPullLine(Data(#"{"status":"pulling 6a0746a1ec1a","digest":"sha256:6a07","total":4000,"completed":1000}"#.utf8))
        XCTAssertEqual(line?.fraction, 0.25)
        XCTAssertEqual(OllamaPullLine(Data(#"{"error":"pull model manifest: file does not exist"}"#.utf8))?.error,
                       "pull model manifest: file does not exist")
        XCTAssertNil(OllamaPullLine(Data(#"{"status":"verifying sha256 digest"}"#.utf8))?.fraction)
    }
}

// MARK: - Runner

private final class ScriptedInstaller: BatchInstalling, @unchecked Sendable {
    let verdicts: [String: BatchItemCheck.Verdict]
    let failures: Set<String>
    let gate: Gate?
    private let lock = NSLock()
    private var _installed: [String] = []

    init(verdicts: [String: BatchItemCheck.Verdict] = [:], failures: Set<String> = [], gate: Gate? = nil) {
        self.verdicts = verdicts
        self.failures = failures
        self.gate = gate
    }

    var installed: [String] { lock.lock(); defer { lock.unlock() }; return _installed }

    func check(_ items: [BatchItem]) async -> [BatchItemCheck] {
        items.map { BatchItemCheck(item: $0, verdict: verdicts[$0.name] ?? .ready, reason: verdicts[$0.name] == .blocked ? "No room" : nil) }
    }

    func install(_ item: BatchItem, progress: @escaping @Sendable (Double?, String?) async -> Void) async -> BatchInstallResult {
        if let gate { await gate.wait() }
        if Task.isCancelled { return .failed("Cancelled.") }
        lock.lock(); _installed.append(item.name); lock.unlock()
        await progress(0.5, "Halfway")
        return failures.contains(item.name) ? .failed("Broke") : .done
    }
}

/// Holds installs until opened, so a test can look at a running batch.
private actor Gate {
    private var open = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if open { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        open = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

private actor LogBook {
    var lines: [String] = []
    func add(_ event: String, _ outcome: String) { lines.append("\(event) → \(outcome)") }
}

final class BatchRunnerTests: XCTestCase {
    private func plan(_ names: [String], id: String = "b1") -> BatchPlan {
        BatchPlan(id: id, name: "Dev box", items: names.map { BatchItem(kind: .brewFormula, name: $0) })
    }

    func testRunsItemsInOrderAndLogsEach() async {
        let installer = ScriptedInstaller(verdicts: ["git": .installed, "big": .blocked], failures: ["bad"])
        let runner = BatchRunner(installer: installer)
        let book = LogBook()
        await runner.start(plan(["git", "uv", "big", "bad"]), by: "Studio MacBook") { await book.add($0, $1) }
        await runner.idle()
        let status = await runner.status(id: "b1").first!
        XCTAssertEqual(status.phase, .finished)
        XCTAssertEqual(status.items.map(\.phase), [.skipped, .done, .skipped, .failed])
        XCTAssertEqual(status.items[0].detail, "Already installed")
        XCTAssertEqual(status.items[3].detail, "Broke")
        XCTAssertEqual(status.startedBy, "Studio MacBook")
        XCTAssertEqual(installer.installed, ["uv", "bad"])
        let lines = await book.lines
        XCTAssertEqual(lines, ["Install Homebrew uv (batch “Dev box”) → Done",
                               "Install Homebrew big (batch “Dev box”) → Skipped: No room",
                               "Install Homebrew bad (batch “Dev box”) → Failed: Broke"])
    }

    func testStartingTheSameBatchTwiceRunsItOnce() async {
        let installer = ScriptedInstaller()
        let runner = BatchRunner(installer: installer)
        await runner.start(plan(["uv"]), by: "A") { _, _ in }
        await runner.start(plan(["uv"]), by: "A") { _, _ in }
        await runner.idle()
        XCTAssertEqual(installer.installed, ["uv"])
        let all = await runner.status()
        XCTAssertEqual(all.count, 1)
    }

    func testBatchesQueueAndCancelStopsTheRest() async throws {
        let gate = Gate()
        let installer = ScriptedInstaller(gate: gate)
        let runner = BatchRunner(installer: installer)
        await runner.start(plan(["a", "b"], id: "first"), by: "A") { _, _ in }
        await runner.start(plan(["c"], id: "second"), by: "A") { _, _ in }
        try await Task.sleep(nanoseconds: 50_000_000)
        let running = await runner.status(id: "first").first!
        XCTAssertEqual(running.phase, .running)
        XCTAssertEqual(running.items[0].phase, .running)
        let second = await runner.status(id: "second").first
        XCTAssertEqual(second?.phase, .queued)

        let cancelledSecond = await runner.cancel(id: "second")
        XCTAssertEqual(cancelledSecond?.phase, .cancelled)
        _ = await runner.cancel(id: "first")
        await gate.release()
        await runner.idle()
        let first = await runner.status(id: "first").first!
        XCTAssertEqual(first.phase, .cancelled)
        XCTAssertEqual(first.items.map(\.phase), [.cancelled, .cancelled])
        XCTAssertEqual(installer.installed, [])
        let unknown = await runner.cancel(id: "nope")
        XCTAssertNil(unknown)
    }

    func testProgressCountsRunningItems() {
        var status = BatchStatus(plan: plan(["a", "b"]), startedBy: "A", createdAt: Date())
        status.items[0].phase = .done
        status.items[1].phase = .running
        status.items[1].progress = 0.5
        XCTAssertEqual(status.progress, 0.75)
    }
}
