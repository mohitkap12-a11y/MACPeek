import Foundation
import MacPeekCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

extension ProcessTarget {
    public init(entry: ProcessEntry) {
        self.init(pid: entry.pid, processName: entry.name, startTime: entry.identityStartTime)
    }
}

extension PermissionService {
    public func capability(for entry: ProcessEntry) -> TerminationCapability {
        capability(pid: entry.pid, user: entry.user)
    }
}

extension TerminationResult {
    public func message(for entry: ProcessEntry) -> String {
        let name = "\(entry.name) (PID \(entry.pid))"
        switch self {
        case .terminated: return "✓ Terminated \(name)."
        case .alreadyExited, .resourceAlreadyReleased: return "\(name) is no longer running."
        case .targetChanged:
            return "PID \(entry.pid) now belongs to a different process than \(entry.name). Nothing was killed. Refresh and try again."
        default: return message(for: ProcessTarget(entry: entry), resourceLabel: "this process")
        }
    }
}

/// ProcessPeek's "resource" is the process itself: it is still *this* process while `ps` lists the PID under the
/// same name. (The shared service additionally compares the kernel start time, so a reused PID is never signalled.)
final class ProcessResource: TerminationResource, @unchecked Sendable {
    private let runner: CommandRunning

    init(runner: CommandRunning) {
        self.runner = runner
    }

    var label: String { "this process" }

    /// `ps -o stat=,comm= -p PID`. Nil when the process is gone or only a zombie (exited, not yet reaped).
    private func current(pid: Int) async throws -> String? {
        let output = try await runner.run("/usr/bin/env", ["LC_ALL=C", "/bin/ps", "-o", "stat=,comm=", "-p", String(pid)])
        let line = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard output.status == 0, !line.isEmpty else { return nil }
        let parts = line.split(maxSplits: 1, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
        guard parts.count == 2 else { return nil }
        if parts[0].hasPrefix("Z") { return nil }
        let command = String(parts[1])
        return command.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? command
    }

    func check(pid: Int) async -> ResourceCheck {
        do {
            guard let name = try await current(pid: pid) else { return .gone }
            return .owned(processName: name)
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    func releaseState(pid: Int) async -> ReleaseState {
        // Once the process has exited nothing is "held"; an unreadable answer is never taken as success.
        do { return try await current(pid: pid) == nil ? .released : .stillHeld } catch { return .stillHeld }
    }
}

/// Ends a process with MacPeek's shared safe-termination service: re-checked, identity-verified, SIGTERM first,
/// and an explicit, separately-validated force kill. Never used automatically.
public struct ProcessTerminator: Sendable {
    private let runner: CommandRunning
    private let service: ProcessTerminationService

    public init(
        runner: CommandRunning = ShellCommand(timeout: 5),
        inspector: ProcessInspecting = SystemProcessInspector(),
        gracePeriod: TimeInterval = 3,
        forceTimeout: TimeInterval = 2,
        pollInterval: TimeInterval = 0.1,
        ownPID: Int = Int(getpid())
    ) {
        self.runner = runner
        self.service = ProcessTerminationService(
            inspector: inspector, gracePeriod: gracePeriod, forceTimeout: forceTimeout,
            pollInterval: pollInterval, ownPID: ownPID)
    }

    /// Graceful termination (SIGTERM). Escalation to SIGKILL is never automatic.
    public func terminate(_ entry: ProcessEntry) async -> TerminationResult {
        await service.terminate(ProcessTarget(entry: entry), resource: ProcessResource(runner: runner))
    }

    /// Explicit SIGKILL; revalidates the process again first.
    public func forceTerminate(_ entry: ProcessEntry) async -> TerminationResult {
        await service.forceTerminate(ProcessTarget(entry: entry), resource: ProcessResource(runner: runner))
    }
}
