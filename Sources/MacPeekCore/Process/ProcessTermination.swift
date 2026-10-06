import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Whether a PID still owns the specific resource (a socket, an open file, …) the user acted on.
public enum ResourceCheck: Equatable, Sendable {
    /// The PID still owns the exact resource; carries the owner's current process name.
    case owned(processName: String)
    /// The resource no longer exists.
    case gone
    /// The resource exists but the PID no longer owns *that* resource (another process, or another socket).
    case changed
    /// The OS could not tell us right now.
    case unavailable(String)
}

public enum ReleaseState: Equatable, Sendable {
    case released
    /// The terminated process let go, but a different process now holds the resource.
    case takenOver(pid: Int)
    case stillHeld
}

/// A resource a utility lets the user free by terminating its owner. Each utility supplies its own
/// (PortPeek: a listening socket; FileLockPeek: an open file). The service never inspects shell output.
public protocol TerminationResource: Sendable {
    /// Lowercase noun phrase for messages, e.g. "port 3000".
    var label: String { get }
    func check(pid: Int) async -> ResourceCheck
    func releaseState(pid: Int) async -> ReleaseState
}

enum TargetValidation: Equatable {
    case valid
    case alreadyExited
    case resourceReleased
    case targetChanged
    case identityUnknown
    case scanFailed(String)
}

/// Safe process termination shared by every utility. Never signals a stale PID: before each signal
/// the resource is re-checked and the process identity (name + start time) re-verified.
public struct ProcessTerminationService: Sendable {
    private let inspector: ProcessInspecting
    private let gracePeriod: TimeInterval
    private let forceTimeout: TimeInterval
    private let pollInterval: TimeInterval
    private let ownPID: Int

    public init(
        inspector: ProcessInspecting = SystemProcessInspector(),
        gracePeriod: TimeInterval = 3,
        forceTimeout: TimeInterval = 2,
        pollInterval: TimeInterval = 0.1,
        ownPID: Int = Int(getpid())
    ) {
        self.inspector = inspector
        self.gracePeriod = gracePeriod
        self.forceTimeout = forceTimeout
        self.pollInterval = pollInterval
        self.ownPID = ownPID
    }

    /// Graceful termination (SIGTERM). Escalation to SIGKILL is never automatic.
    public func terminate(_ target: ProcessTarget, resource: TerminationResource) async -> TerminationResult {
        await send(SIGTERM, to: target, resource: resource, wait: gracePeriod)
    }

    /// Explicit SIGKILL. Revalidates the target again before signalling.
    public func forceTerminate(_ target: ProcessTarget, resource: TerminationResource) async -> TerminationResult {
        await send(SIGKILL, to: target, resource: resource, wait: forceTimeout)
    }

    private func send(
        _ signal: Int32, to target: ProcessTarget, resource: TerminationResource, wait: TimeInterval
    ) async -> TerminationResult {
        if target.pid <= 1 || target.pid == ownPID {
            return .failed("Refusing to signal a protected process.")
        }

        switch await validateTarget(target, resource: resource) {
        case .valid: break
        case .alreadyExited: return .alreadyExited
        case .resourceReleased: return .resourceAlreadyReleased
        case .targetChanged: return .targetChanged
        case .identityUnknown:
            return .failed("Could not verify the process identity, so nothing was killed. Refresh and try again.")
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
        switch await verifyReleased(target, resource: resource) {
        case .released: return .terminated
        case .takenOver(let pid):
            return .failed("The process exited, but \(resource.label) is now in use by another process (PID \(pid)).")
        case .stillHeld: return .failed("The process exited but \(resource.label) is still in use.")
        }
    }

    // MARK: - Steps

    func validateTarget(_ target: ProcessTarget, resource: TerminationResource) async -> TargetValidation {
        switch await resource.check(pid: target.pid) {
        case .unavailable(let reason): return .scanFailed(reason)
        case .gone: return inspector.isAlive(pid: target.pid) ? .resourceReleased : .alreadyExited
        case .changed: return .targetChanged
        case .owned(let name): if name != target.processName { return .targetChanged }
        }

        // PID-reuse guard: identity must be provable. A missing timestamp never counts as a match.
        guard let expected = target.startTime else { return .identityUnknown }
        guard let current = inspector.startTime(pid: target.pid) else {
            return inspector.isAlive(pid: target.pid) ? .identityUnknown : .alreadyExited
        }
        return abs(expected - current) > 1 ? .targetChanged : .valid // same PID, different process
    }

    func waitForExit(pid: Int, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while inspector.isAlive(pid: pid) {
            if Date() >= deadline { return false }
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
        return true
    }

    /// The kernel can lag slightly behind process exit, so poll briefly. "Released" means *nobody*
    /// holds the resource: a replacement process taking it must not be reported as freed.
    func verifyReleased(_ target: ProcessTarget, resource: TerminationResource) async -> ReleaseState {
        let deadline = Date().addingTimeInterval(1)
        var last = ReleaseState.stillHeld
        repeat {
            let state = await resource.releaseState(pid: target.pid)
            if state != .stillHeld { return state }
            last = state
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        } while Date() < deadline
        return last
    }
}
