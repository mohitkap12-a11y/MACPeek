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

    public func scan(path: String) async throws -> FileLockScan {
        let scan = try await discovery.scan(path: path)
        return scan.withHolders(scan.holders.map { $0.withStartTime(inspector.startTime(pid: $0.pid)) })
    }

    public func holders(of path: String) async throws -> [FileLockHolder] {
        try await scan(path: path).holders
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
/// One instance is used for a whole terminate attempt: it remembers who held the path when the target was
/// checked, so that processes that were *already* holding it are not mistaken for a replacement.
final class FileLockResource: TerminationResource, @unchecked Sendable {
    let path: String
    let discovery: FileLockDiscoveryProtocol
    private let lock = NSLock()
    private var holdersBefore: Set<Int> = []

    init(path: String, discovery: FileLockDiscoveryProtocol) {
        self.path = path
        self.discovery = discovery
    }

    static func label(for path: String) -> String { "“\(URL(fileURLWithPath: path).lastPathComponent)”" }
    var label: String { Self.label(for: path) }

    func check(pid: Int) async -> ResourceCheck {
        let holders: [FileLockHolder]
        do { holders = try await discovery.holders(of: path) } catch FileLockError.notFound {
            return .gone // the file no longer exists, so nothing can hold it
        } catch {
            return .unavailable(error.localizedDescription)
        }
        lock.lock(); holdersBefore = Set(holders.map(\.pid)); lock.unlock()
        guard !holders.isEmpty else { return .gone }
        guard let holder = holders.first(where: { $0.pid == pid }) else { return .changed }
        return .owned(processName: holder.processName)
    }

    func releaseState(pid: Int) async -> ReleaseState {
        let holders: [FileLockHolder]
        do { holders = try await discovery.holders(of: path) } catch FileLockError.notFound {
            return .released // the holder removed the file as it exited (lock files, temp files, journals)
        } catch {
            return .stillHeld // could not tell; keep polling, never claim success
        }
        if holders.contains(where: { $0.pid == pid }) { return .stillHeld }
        lock.lock(); let before = holdersBefore; lock.unlock()
        // Only a process that was NOT holding the path before counts as a replacement. Other processes that
        // already held it keep holding it; that is not a failure to release by the terminated one.
        if let newcomer = holders.first(where: { !before.contains($0.pid) }) { return .takenOver(pid: newcomer.pid) }
        return .released
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
