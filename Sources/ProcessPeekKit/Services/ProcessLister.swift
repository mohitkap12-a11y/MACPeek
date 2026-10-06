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
    /// True when the PID no longer belongs to the process that was listed (it exited and the PID was reused).
    /// Nothing about the replacement process is returned in that case.
    public let processChanged: Bool
    /// The full command line. It may contain tokens or passwords that were passed as arguments, so it is only
    /// read on request, shown on screen, and never logged.
    public let commandLine: String?
    public let listeningPorts: [PortInfo]
    /// Set when the ports could not be listed (the rest of the details are still valid).
    public let portsNote: String?

    public init(pid: Int, processChanged: Bool = false, commandLine: String?, listeningPorts: [PortInfo], portsNote: String?) {
        self.pid = pid
        self.processChanged = processChanged
        self.commandLine = commandLine
        self.listeningPorts = listeningPorts
        self.portsNote = portsNote
    }
}

public protocol ProcessListing: Sendable {
    func snapshot() async throws -> ProcessSnapshot
    /// Details for the process in `entry`. Its start time is used to make sure the PID still belongs to it.
    func details(for entry: ProcessEntry) async throws -> ProcessDetails
}

/// Reads the process table with `ps`, the command line with `ps -ww -o lstart=,args=`, and listening ports through
/// PortPeek's lsof discovery. Everything is read-only.
///
/// `ps` prints `lstart` with the user's locale, so it is always run as `env LC_ALL=C ps …`: the parser only
/// understands the C-locale form, and a German or French Mac would otherwise show an empty list.
public struct PSProcessLister: ProcessListing {
    static let env = "/usr/bin/env"
    static let ps = "/bin/ps"
    static let listArguments = ["LC_ALL=C", ps, "-axo", "pid,ppid,uid,user,state,lstart,etime,%cpu,rss,comm"]
    private let runner: CommandRunning
    private let ports: PortDiscoveryProtocol

    public init(runner: CommandRunning = ShellCommand(timeout: 15), ports: PortDiscoveryProtocol = LsofPortDiscovery()) {
        self.runner = runner
        self.ports = ports
    }

    public func snapshot() async throws -> ProcessSnapshot {
        let output = try await runner.run(Self.env, Self.listArguments)
        guard output.status == 0 else {
            let detail = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ProcessListError.commandFailed(detail.isEmpty ? "ps exited with status \(output.status)" : detail)
        }
        let entries = PSParser.parse(output.stdout)
        // A header plus rows that all fail to parse means the format changed: say so instead of showing "no processes".
        let lines = output.stdout.split(separator: "\n", omittingEmptySubsequences: true).count
        if entries.isEmpty && lines > 1 {
            throw ProcessListError.commandFailed("ps printed process information in a format MacPeek does not understand.")
        }
        return ProcessSnapshot(entries: entries)
    }

    private static let startAndArgs = NSRegularExpression.compile(
        #"^\s*([A-Z][a-z]{2} [A-Z][a-z]{2}\s+\d{1,2} \d{2}:\d{2}:\d{2} \d{4})\s*(.*?)\s*$"#)

    public func details(for entry: ProcessEntry) async throws -> ProcessDetails {
        let pid = entry.pid
        guard let first = try await identityAndCommandLine(pid: pid) else {
            // `ps` found no such process: it has exited.
            return ProcessDetails(pid: pid, processChanged: true, commandLine: nil, listeningPorts: [], portsNote: nil)
        }
        guard Self.sameProcess(first.startTime, entry.startTime) else {
            return ProcessDetails(pid: pid, processChanged: true, commandLine: nil, listeningPorts: [], portsNote: nil)
        }

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

        // The lsof run takes a moment: confirm the PID still belongs to the same process afterwards.
        let after = try await identityAndCommandLine(pid: pid)
        guard let after, Self.sameProcess(after.startTime, entry.startTime) else {
            return ProcessDetails(pid: pid, processChanged: true, commandLine: nil, listeningPorts: [], portsNote: nil)
        }
        return ProcessDetails(pid: pid, commandLine: first.commandLine.isEmpty ? nil : first.commandLine,
                              listeningPorts: listening, portsNote: note)
    }

    private struct Identity {
        let startTime: Date?
        let commandLine: String
    }

    /// `ps -ww -o lstart=,args= -p PID`. Nil when the process does not exist. `-ww` stops `ps` truncating the line.
    private func identityAndCommandLine(pid: Int) async throws -> Identity? {
        let output = try await runner.run(Self.env, ["LC_ALL=C", Self.ps, "-ww", "-o", "lstart=,args=", "-p", String(pid)])
        let line = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard output.status == 0, !line.isEmpty else { return nil }
        guard let g = Self.startAndArgs.groups(in: line), let started = g[1] else {
            return Identity(startTime: nil, commandLine: "")
        }
        return Identity(startTime: PSParser.date(from: started), commandLine: g[2] ?? "")
    }

    /// Two start times identify the same process when they agree to the second. If either is unknown the process
    /// cannot be confirmed, so it is treated as changed rather than risk showing another process's details.
    static func sameProcess(_ lhs: Date?, _ rhs: Date?) -> Bool {
        guard let lhs, let rhs else { return false }
        return abs(lhs.timeIntervalSince(rhs)) < 1.5
    }
}
