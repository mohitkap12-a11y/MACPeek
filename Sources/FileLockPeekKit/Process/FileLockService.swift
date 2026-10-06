import Foundation
import MacPeekCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Scan entry point for the app: discovery plus process start-time enrichment, which is what lets the
/// shared termination service detect PID reuse later.
public struct FileLockService: Sendable {
    private let discovery: FileLockDiscoveryProtocol
    private let inspector: ProcessInspecting

    public init(discovery: FileLockDiscoveryProtocol = LsofFileLockDiscovery(), inspector: ProcessInspecting = SystemProcessInspector()) {
        self.discovery = discovery
        self.inspector = inspector
    }

    public func holders(of path: String) async throws -> [FileLockHolder] {
        try await discovery.holders(of: path).map { $0.withStartTime(inspector.startTime(pid: $0.pid)) }
    }
}

extension ProcessTarget {
    public init(holder: FileLockHolder) {
        self.init(pid: holder.pid, processName: holder.processName, startTime: holder.startTime)
    }
}

extension TerminationResult {
    public func message(for holder: FileLockHolder, path: String) -> String {
        message(for: ProcessTarget(holder: holder), resourceLabel: FileLockResource.label(for: path))
    }
}

/// FileLockPeek's resource: "this process holds this path".
struct FileLockResource: TerminationResource {
    let path: String
    let discovery: FileLockDiscoveryProtocol

    static func label(for path: String) -> String { "“\(URL(fileURLWithPath: path).lastPathComponent)”" }
    var label: String { Self.label(for: path) }

    func check(pid: Int) async -> ResourceCheck {
        let holders: [FileLockHolder]
        do { holders = try await discovery.holders(of: path) } catch {
            return .unavailable(error.localizedDescription)
        }
        guard !holders.isEmpty else { return .gone }
        guard let holder = holders.first(where: { $0.pid == pid }) else { return .changed }
        return .owned(processName: holder.processName)
    }

    func releaseState(pid: Int) async -> ReleaseState {
        guard let holders = try? await discovery.holders(of: path) else { return .stillHeld }
        if holders.isEmpty { return .released }
        if holders.contains(where: { $0.pid == pid }) { return .stillHeld }
        return .takenOver(pid: holders[0].pid)
    }
}

/// Ends a holder using MacPeek's shared safe-termination service. Never used automatically.
public struct FileLockTerminator: Sendable {
    private let discovery: FileLockDiscoveryProtocol
    private let service: ProcessTerminationService

    public init(
        discovery: FileLockDiscoveryProtocol,
        inspector: ProcessInspecting = SystemProcessInspector(),
        gracePeriod: TimeInterval = 3,
        forceTimeout: TimeInterval = 2,
        pollInterval: TimeInterval = 0.1,
        ownPID: Int = Int(getpid())
    ) {
        self.discovery = discovery
        self.service = ProcessTerminationService(
            inspector: inspector, gracePeriod: gracePeriod, forceTimeout: forceTimeout,
            pollInterval: pollInterval, ownPID: ownPID
        )
    }

    /// Graceful termination (SIGTERM). Escalation to SIGKILL is never automatic.
    public func terminate(_ holder: FileLockHolder, holding path: String) async -> TerminationResult {
        await service.terminate(ProcessTarget(holder: holder), resource: FileLockResource(path: path, discovery: discovery))
    }

    /// Explicit SIGKILL; revalidates again first.
    public func forceTerminate(_ holder: FileLockHolder, holding path: String) async -> TerminationResult {
        await service.forceTerminate(ProcessTarget(holder: holder), resource: FileLockResource(path: path, discovery: discovery))
    }
}

extension PermissionService {
    public func capability(for holder: FileLockHolder) -> TerminationCapability {
        capability(pid: holder.pid, user: holder.user)
    }
}
