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

    public func capability(pid: Int, user: String?) -> TerminationCapability {
        if pid <= 1 || pid == ownPID { return .protected }
        guard let user, user != currentUser else { return .canTerminate }
        return user == "root" ? .protected : .permissionRequired
    }
}
