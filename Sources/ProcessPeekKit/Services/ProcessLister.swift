import Foundation
import MacPeekCore
import PortPeekKit

public enum ProcessListError: Error, Equatable, LocalizedError {
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let detail): return detail
        }
    }
}

/// What is known about one process beyond its `ps` row, loaded only when the user opens it.
public struct ProcessDetails: Equatable, Sendable {
    public let pid: Int
    /// The full command line. It may contain tokens or passwords that were passed as arguments, so it is only
    /// read on request, shown on screen, and never logged.
    public let commandLine: String?
    public let listeningPorts: [PortInfo]
    /// Set when the ports could not be listed (the rest of the details are still valid).
    public let portsNote: String?

    public init(pid: Int, commandLine: String?, listeningPorts: [PortInfo], portsNote: String?) {
        self.pid = pid
        self.commandLine = commandLine
        self.listeningPorts = listeningPorts
        self.portsNote = portsNote
    }
}

public protocol ProcessListing: Sendable {
    func snapshot() async throws -> ProcessSnapshot
    func details(for pid: Int) async throws -> ProcessDetails
}

/// Reads the process table with `ps`, the command line with `ps -ww -o args=`, and listening ports through
/// PortPeek's lsof discovery. Everything is read-only.
public struct PSProcessLister: ProcessListing {
    static let ps = "/bin/ps"
    static let listArguments = ["-axo", "pid,ppid,uid,user,state,lstart,etime,%cpu,rss,comm"]
    private let runner: CommandRunning
    private let ports: PortDiscoveryProtocol

    public init(runner: CommandRunning = ShellCommand(timeout: 15), ports: PortDiscoveryProtocol = LsofPortDiscovery()) {
        self.runner = runner
        self.ports = ports
    }

    public func snapshot() async throws -> ProcessSnapshot {
        let output = try await runner.run(Self.ps, Self.listArguments)
        guard output.status == 0 else {
            let detail = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ProcessListError.commandFailed(detail.isEmpty ? "ps exited with status \(output.status)" : detail)
        }
        return ProcessSnapshot(entries: PSParser.parse(output.stdout))
    }

    public func details(for pid: Int) async throws -> ProcessDetails {
        // `-ww` stops ps truncating the line to the terminal width. Status 1 means the process is gone.
        let args = try await runner.run(Self.ps, ["-ww", "-o", "args=", "-p", String(pid)])
        let line = args.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let commandLine = args.status == 0 && !line.isEmpty ? line : nil

        try Task.checkCancellation()
        var listening: [PortInfo] = []
        var note: String?
        do {
            listening = try await ports.discover().filter { $0.pid == pid }
        } catch is CancellationError {
            throw CancellationError()
        } catch CommandError.cancelled {
            throw CommandError.cancelled
        } catch {
            note = "Listening ports could not be read."
        }
        return ProcessDetails(pid: pid, commandLine: commandLine, listeningPorts: listening, portsNote: note)
    }
}
