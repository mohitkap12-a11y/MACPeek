import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

enum TargetValidation: Equatable {
    case valid
    case alreadyExited
    case portAlreadyReleased
    case targetChanged
    case scanFailed(String)
}

/// Safe process termination. Never signals a stale PID: the target is re-scanned and
/// its identity (port ownership, name, start time) re-verified before every signal.
public struct KillService: Sendable {
    private let discovery: PortDiscoveryProtocol
    private let inspector: ProcessInspecting
    private let gracePeriod: TimeInterval
    private let forceTimeout: TimeInterval
    private let pollInterval: TimeInterval
    private let ownPID: Int

    public init(
        discovery: PortDiscoveryProtocol,
        inspector: ProcessInspecting = SystemProcessInspector(),
        gracePeriod: TimeInterval = 3,
        forceTimeout: TimeInterval = 2,
        pollInterval: TimeInterval = 0.1,
        ownPID: Int = Int(getpid())
    ) {
        self.discovery = discovery
        self.inspector = inspector
        self.gracePeriod = gracePeriod
        self.forceTimeout = forceTimeout
        self.pollInterval = pollInterval
        self.ownPID = ownPID
    }

    /// Graceful termination (SIGTERM). Escalation to SIGKILL is never automatic.
    public func terminate(_ target: PortInfo) async -> TerminationResult {
        await send(SIGTERM, to: target, wait: gracePeriod)
    }

    /// Explicit SIGKILL. Revalidates the target again before signalling.
    public func forceTerminate(_ target: PortInfo) async -> TerminationResult {
        await send(SIGKILL, to: target, wait: forceTimeout)
    }

    private func send(_ signal: Int32, to target: PortInfo, wait: TimeInterval) async -> TerminationResult {
        if target.pid <= 1 || target.pid == ownPID {
            return .failed("Refusing to signal a protected process.")
        }

        switch await validateTarget(target) {
        case .valid: break
        case .alreadyExited: return .alreadyExited
        case .portAlreadyReleased: return .portAlreadyReleased
        case .targetChanged: return .targetChanged
        case .scanFailed(let reason): return .failed(reason)
        }

        let errorCode = inspector.signal(pid: target.pid, signal: signal)
        switch errorCode {
        case 0: break
        case ESRCH: return .alreadyExited
        case EPERM: return .permissionDenied
        default: return .failed(String(cString: strerror(errorCode)))
        }

        guard await waitForExit(pid: target.pid, timeout: wait) else { return .stillRunning }
        if await verifyPortReleased(target) { return .terminated }
        return .failed("The process exited but port \(target.port) is still in use.")
    }

    // MARK: - Steps

    func validateTarget(_ target: PortInfo) async -> TargetValidation {
        let scan: [PortInfo]
        do { scan = try await discovery.discover() } catch {
            return .scanFailed(error.localizedDescription)
        }
        let onPort = scan.filter { $0.port == target.port && $0.protocolType == target.protocolType }

        guard !onPort.isEmpty else {
            return inspector.isAlive(pid: target.pid) ? .portAlreadyReleased : .alreadyExited
        }
        guard let owner = onPort.first(where: { $0.pid == target.pid }) else { return .targetChanged }
        if owner.processName != target.processName { return .targetChanged }

        if let expected = target.startTime, let current = inspector.startTime(pid: target.pid),
           abs(expected - current) > 1 {
            return .targetChanged // same PID, different process: PID was reused
        }
        return .valid
    }

    func waitForExit(pid: Int, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while inspector.isAlive(pid: pid) {
            if Date() >= deadline { return false }
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
        return true
    }

    /// The kernel can lag slightly behind process exit, so poll briefly.
    func verifyPortReleased(_ target: PortInfo) async -> Bool {
        let deadline = Date().addingTimeInterval(1)
        repeat {
            if let scan = try? await discovery.discover(),
               !scan.contains(where: { $0.pid == target.pid && $0.port == target.port && $0.protocolType == target.protocolType }) {
                return true
            }
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        } while Date() < deadline
        return false
    }
}
