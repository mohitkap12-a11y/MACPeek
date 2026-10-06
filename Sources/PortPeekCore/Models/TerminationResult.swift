import Foundation

public enum TerminationResult: Equatable, Sendable {
    case terminated
    case alreadyExited
    case portAlreadyReleased
    case permissionDenied
    case targetChanged
    /// SIGTERM was delivered but the process is still running. The UI may offer an explicit force-kill.
    case stillRunning
    case failed(String)

    public var isSuccess: Bool {
        switch self {
        case .terminated, .alreadyExited, .portAlreadyReleased: return true
        default: return false
        }
    }

    public func message(for target: PortInfo) -> String {
        switch self {
        case .terminated:
            return "Port \(target.port) freed — \(target.processName) (PID \(target.pid)) was terminated."
        case .alreadyExited:
            return "\(target.processName) (PID \(target.pid)) had already exited."
        case .portAlreadyReleased:
            return "Port \(target.port) is already free."
        case .permissionDenied:
            return "Permission denied. \(target.processName) (PID \(target.pid)) cannot be terminated by the current user."
        case .targetChanged:
            return "Port \(target.port) is now used by a different process. Nothing was killed — refresh and try again."
        case .stillRunning:
            return "\(target.processName) (PID \(target.pid)) did not exit after SIGTERM."
        case .failed(let reason):
            return "Could not terminate \(target.processName) (PID \(target.pid)): \(reason)"
        }
    }
}
