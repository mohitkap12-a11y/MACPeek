import Foundation

/// Source of truth for "which ports are in use". The rest of the app depends only on this,
/// never on shell output, so a native (libproc) implementation can replace lsof later.
public protocol PortDiscoveryProtocol: Sendable {
    func discover() async throws -> [PortInfo]
}

public enum PortDiscoveryError: Error, LocalizedError, Equatable {
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let detail): return "Port scan failed: \(detail)"
        }
    }
}
