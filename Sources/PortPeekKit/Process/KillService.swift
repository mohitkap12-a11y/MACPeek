import Foundation
import MacPeekCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

extension ProcessTarget {
    public init(port: PortInfo) {
        self.init(pid: port.pid, processName: port.processName, startTime: port.startTime)
    }
}

extension TerminationResult {
    public func message(for port: PortInfo) -> String {
        message(for: ProcessTarget(port: port), resourceLabel: "port \(port.port)")
    }
}

extension PermissionService {
    public func capability(for port: PortInfo) -> TerminationCapability {
        capability(pid: port.pid, user: port.user)
    }
}

/// PortPeek's resource: one listening socket (PID + address + port + protocol).
struct PortResource: TerminationResource {
    let port: PortInfo
    let discovery: PortDiscoveryProtocol

    var label: String { "port \(port.port)" }

    private func owners(_ scan: [PortInfo]) -> [PortInfo] {
        scan.filter { $0.port == port.port && $0.protocolType == port.protocolType }
    }

    func check(pid: Int) async -> ResourceCheck {
        let scan: [PortInfo]
        do { scan = try await discovery.discover() } catch {
            return .unavailable(error.localizedDescription)
        }
        let onPort = owners(scan)
        guard !onPort.isEmpty else { return .gone }
        // The selected *socket* (pid + address) must still exist: a process that closed only the
        // selected address but still listens elsewhere on the port must not be killed for it.
        guard let owner = onPort.first(where: { $0.pid == pid && $0.address == port.address }) else {
            return .changed
        }
        return .owned(processName: owner.processName)
    }

    func releaseState(pid: Int) async -> ReleaseState {
        guard let scan = try? await discovery.discover() else { return .stillHeld }
        let onPort = owners(scan)
        if onPort.isEmpty { return .released }
        if !onPort.contains(where: { $0.pid == pid }), let other = onPort.first {
            return .takenOver(pid: other.pid)
        }
        return .stillHeld
    }
}

/// Terminates the process behind a port using MacPeek's shared safe-termination service.
public struct KillService: Sendable {
    private let discovery: PortDiscoveryProtocol
    private let service: ProcessTerminationService

    public init(
        discovery: PortDiscoveryProtocol,
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
    public func terminate(_ port: PortInfo) async -> TerminationResult {
        await service.terminate(ProcessTarget(port: port), resource: PortResource(port: port, discovery: discovery))
    }

    /// Explicit SIGKILL; revalidates again first.
    public func forceTerminate(_ port: PortInfo) async -> TerminationResult {
        await service.forceTerminate(ProcessTarget(port: port), resource: PortResource(port: port, discovery: discovery))
    }
}
