import Foundation
import MacPeekCore

public enum SleepError: Error, Equatable, LocalizedError {
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let detail): return detail
        }
    }
}

public struct SleepSnapshot: Equatable, Sendable {
    public let report: AssertionReport
    public let settings: PowerSettings?
    public let diagnosis: SleepDiagnosis

    public init(report: AssertionReport, settings: PowerSettings?, diagnosis: SleepDiagnosis) {
        self.report = report
        self.settings = settings
        self.diagnosis = diagnosis
    }
}

public protocol SleepReading: Sendable {
    /// Fast: current assertions and settings.
    func snapshot() async throws -> SleepSnapshot
    /// Slow (can take tens of seconds): recent sleep/wake events from the power log.
    func history(limit: Int) async throws -> SleepHistory
}

/// Reads `pmset` (read-only; SleepPeek never changes a power setting or runs `pmset` with write flags).
public struct PMSetSleepReader: SleepReading {
    static let pmset = "/usr/bin/pmset"
    private let runner: CommandRunning
    private let historyRunner: CommandRunning

    /// `pmset -g log` was observed taking longer than 20 seconds on a Mac, so history gets its own, longer timeout.
    public init(runner: CommandRunning = ShellCommand(timeout: 10), historyRunner: CommandRunning = ShellCommand(timeout: 90)) {
        self.runner = runner
        self.historyRunner = historyRunner
    }

    public func snapshot() async throws -> SleepSnapshot {
        let assertions = try await run(runner, ["-g", "assertions"])
        let report = AssertionParser.parse(assertions)
        // Settings only add macOS's own "prevented by" summary: a failure here is not fatal.
        var settings: PowerSettings?
        if let text = try? await run(runner, ["-g"]) { settings = PowerSettingsParser.parse(text) }
        try Task.checkCancellation()
        return SleepSnapshot(report: report, settings: settings, diagnosis: SleepAnalysis.diagnose(report: report, settings: settings))
    }

    public func history(limit: Int = 60) async throws -> SleepHistory {
        SleepLogParser.parse(try await run(historyRunner, ["-g", "log"]), limit: limit)
    }

    private func run(_ runner: CommandRunning, _ arguments: [String]) async throws -> String {
        let output = try await runner.run(Self.pmset, arguments)
        guard output.status == 0 else {
            let detail = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SleepError.commandFailed(detail.isEmpty ? "pmset exited with status \(output.status)" : detail)
        }
        return output.stdout
    }
}
