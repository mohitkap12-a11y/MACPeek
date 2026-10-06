import Foundation
import MacPeekCore

public enum DisplayError: Error, Equatable, LocalizedError {
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let detail): return detail
        }
    }
}

public protocol DisplayDiscovering: Sendable {
    func report() async throws -> DisplayReport
}

/// Reads display information with `system_profiler SPDisplaysDataType -json` (read-only, no permissions).
public struct SystemProfilerDisplayDiscovery: DisplayDiscovering {
    static let executable = "/usr/sbin/system_profiler"
    static let arguments = ["SPDisplaysDataType", "-json"]
    private let runner: CommandRunning

    // system_profiler can take a couple of seconds on Macs with several displays.
    public init(runner: CommandRunning = ShellCommand(timeout: 20)) {
        self.runner = runner
    }

    public func report() async throws -> DisplayReport {
        let output = try await runner.run(Self.executable, Self.arguments)
        guard output.status == 0 else {
            let detail = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw DisplayError.commandFailed(detail.isEmpty ? "system_profiler exited with status \(output.status)" : detail)
        }
        return try DisplayParser.parse(output.stdout)
    }
}
