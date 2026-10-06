import Foundation

/// The process a user asked to terminate, as it was when they saw it.
/// `startTime` is what distinguishes it from a later process that reuses the same PID.
public struct ProcessTarget: Hashable, Sendable {
    public let pid: Int
    public let processName: String
    public let startTime: TimeInterval?

    public init(pid: Int, processName: String, startTime: TimeInterval?) {
        self.pid = pid
        self.processName = processName
        self.startTime = startTime
    }
}

public enum TerminationResult: Equatable, Sendable {
    case terminated
    case alreadyExited
    /// The process is alive but no longer holds the resource (port, file, …); nothing was signalled.
    case resourceAlreadyReleased
    case permissionDenied
    case targetChanged
    /// SIGTERM was delivered but the process is still running. The UI may offer an explicit force-kill.
    case stillRunning
    case failed(String)

    public var isSuccess: Bool {
        switch self {
        case .terminated, .alreadyExited, .resourceAlreadyReleased: return true
        default: return false
        }
    }

    /// `resourceLabel` is a lowercase noun phrase such as "port 3000".
    public func message(for target: ProcessTarget, resourceLabel: String) -> String {
        let name = "\(target.processName) (PID \(target.pid))"
        switch self {
        case .terminated:
            return "\(resourceLabel.capitalizedFirst) freed — \(name) was terminated."
        case .alreadyExited:
            return "\(name) had already exited."
        case .resourceAlreadyReleased:
            return "\(resourceLabel.capitalizedFirst) is already free."
        case .permissionDenied:
            return "Permission denied. \(name) cannot be terminated by the current user."
        case .targetChanged:
            return "\(resourceLabel.capitalizedFirst) is now used by a different process. Nothing was killed — refresh and try again."
        case .stillRunning:
            return "\(name) did not exit after SIGTERM."
        case .failed(let reason):
            return "Could not terminate \(name): \(reason)"
        }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + String(dropFirst()) }
}
