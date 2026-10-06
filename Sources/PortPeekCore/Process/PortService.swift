import Foundation

/// Scan entry point for the app: discovery plus process start-time enrichment,
/// which is what lets `KillService` detect PID reuse later.
public struct PortService: Sendable {
    private let discovery: PortDiscoveryProtocol
    private let inspector: ProcessInspecting

    public init(discovery: PortDiscoveryProtocol = LsofPortDiscovery(), inspector: ProcessInspecting = SystemProcessInspector()) {
        self.discovery = discovery
        self.inspector = inspector
    }

    public func scan() async throws -> [PortInfo] {
        let ports = try await discovery.discover()
        var startTimes: [Int: TimeInterval?] = [:]
        return ports.map { port in
            if startTimes[port.pid] == nil { startTimes[port.pid] = .some(inspector.startTime(pid: port.pid)) }
            return port.withStartTime(startTimes[port.pid] ?? nil)
        }
    }
}
