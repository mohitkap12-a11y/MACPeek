import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum TerminationCapability: Equatable, Sendable {
    case canTerminate
    case permissionRequired
    case protected

    public var label: String {
        switch self {
        case .canTerminate: return "Can terminate"
        case .permissionRequired: return "Permission required"
        case .protected: return "Protected/system process"
        }
    }
}

/// Predicts whether the current user can terminate a process. Never elevates privileges.
public struct PermissionService: Sendable {
    private let currentUser: String
    private let ownPID: Int

    public init(currentUser: String = NSUserName(), ownPID: Int = Int(getpid())) {
        self.currentUser = currentUser
        self.ownPID = ownPID
    }

    public func capability(for port: PortInfo) -> TerminationCapability {
        if port.pid <= 1 || port.pid == ownPID { return .protected }
        guard let user = port.user, user != currentUser else { return .canTerminate }
        return user == "root" ? .protected : .permissionRequired
    }
}
