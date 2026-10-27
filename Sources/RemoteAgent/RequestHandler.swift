import Foundation
import MacPeekCore
import CPUPeekKit
import MemoryPeekKit
import DiskPeekKit
import NetPeekKit
import PortPeekKit
import ProcessPeekKit
import SleepPeekKit
import DNSPeekKit
import RemoteProtocol

/// Where the agent's answers come from. `system()` uses the same readers as MacPeek's own utilities; tests pass fakes.
public struct AgentReaders: Sendable {
    public var device: @Sendable () -> DeviceInfo
    public var cpuTopology: @Sendable () -> CPUTopology
    public var cpuSnapshot: @Sendable () throws -> CPUSnapshot
    public var memory: @Sendable () throws -> MemoryStats
    public var processUsage: @Sendable () throws -> ProcessUsageSnapshot
    public var volumes: @Sendable () throws -> [VolumeCapacity]
    public var networkCounters: @Sendable () throws -> [InterfaceCounters]
    public var networkSnapshot: @Sendable () async throws -> NetSnapshot
    public var ports: @Sendable () async throws -> [PortInfo]
    public var processes: @Sendable () async throws -> ProcessSnapshot
    public var sleep: @Sendable () async throws -> SleepSnapshot
    public var dnsConfiguration: @Sendable () async throws -> DNSConfiguration
    public var dnsProbe: @Sendable (_ server: String, _ name: String) async throws -> ServerProbe

    public init(device: @escaping @Sendable () -> DeviceInfo, cpuTopology: @escaping @Sendable () -> CPUTopology,
                cpuSnapshot: @escaping @Sendable () throws -> CPUSnapshot, memory: @escaping @Sendable () throws -> MemoryStats,
                processUsage: @escaping @Sendable () throws -> ProcessUsageSnapshot,
                volumes: @escaping @Sendable () throws -> [VolumeCapacity],
                networkCounters: @escaping @Sendable () throws -> [InterfaceCounters],
                networkSnapshot: @escaping @Sendable () async throws -> NetSnapshot,
                ports: @escaping @Sendable () async throws -> [PortInfo],
                processes: @escaping @Sendable () async throws -> ProcessSnapshot,
                sleep: @escaping @Sendable () async throws -> SleepSnapshot,
                dnsConfiguration: @escaping @Sendable () async throws -> DNSConfiguration = {
                    throw RemoteError(.unavailable, "DNS is not available here.")
                },
                dnsProbe: @escaping @Sendable (String, String) async throws -> ServerProbe = { _, _ in
                    throw RemoteError(.unavailable, "DNS is not available here.")
                }) {
        self.device = device
        self.cpuTopology = cpuTopology
        self.cpuSnapshot = cpuSnapshot
        self.memory = memory
        self.processUsage = processUsage
        self.volumes = volumes
        self.networkCounters = networkCounters
        self.networkSnapshot = networkSnapshot
        self.ports = ports
        self.processes = processes
        self.sleep = sleep
        self.dnsConfiguration = dnsConfiguration
        self.dnsProbe = dnsProbe
    }

    public static func system() -> AgentReaders {
        let cpu = SystemCPUReader(), memory = SystemMemoryReader(), usage = SystemProcessUsageReader()
        let volumes = SystemVolumeCapacityReader(), counters = SystemInterfaceCountersReader(), network = SystemNetworkReader()
        let ports = PortService(), processes = PSProcessLister(), sleep = PMSetSleepReader(), device = SystemDeviceInfoReader()
        let dns = SystemDNSReader()
        return AgentReaders(device: { device.read() }, cpuTopology: { cpu.topology() }, cpuSnapshot: { try cpu.snapshot() },
                            memory: { try memory.read() }, processUsage: { try usage.read(isCancelled: { false }) },
                            volumes: { try volumes.read() }, networkCounters: { try counters.read() },
                            networkSnapshot: { try await network.snapshot() }, ports: { try await ports.scan() },
                            processes: { try await processes.snapshot() }, sleep: { try await sleep.snapshot() },
                            dnsConfiguration: { try await dns.configuration() },
                            dnsProbe: { server, name in try await dns.probe(server: server, name: name) })
    }
}

/// How the agent carries out actions. `system()` uses MacPeek's safe-termination services, which re-check the target
/// (same process, still holding the port) before any signal and never escalate to SIGKILL on their own.
public struct AgentActions: Sendable {
    public var freePort: @Sendable (PortInfo, _ force: Bool) async -> TerminationResult
    public var quitProcess: @Sendable (ProcessEntry, _ force: Bool) async -> TerminationResult

    public init(freePort: @escaping @Sendable (PortInfo, Bool) async -> TerminationResult,
                quitProcess: @escaping @Sendable (ProcessEntry, Bool) async -> TerminationResult) {
        self.freePort = freePort
        self.quitProcess = quitProcess
    }

    public static func system() -> AgentActions {
        let kill = KillService(discovery: LsofPortDiscovery()), terminator = ProcessTerminator()
        return AgentActions(freePort: { port, force in force ? await kill.forceTerminate(port) : await kill.terminate(port) },
                            quitProcess: { entry, force in
                                force ? await terminator.forceTerminate(entry) : await terminator.terminate(entry)
                            })
    }
}

/// Answers one decrypted request from a paired console.
public struct RequestHandler: Sendable {
    /// For the activity log: what an action was and how it ended.
    public struct ActionRecord: Equatable, Sendable {
        public let event: String
        public let outcome: String
    }

    let readers: AgentReaders
    let actions: AgentActions
    let agentVersion: String

    public init(readers: AgentReaders, actions: AgentActions, agentVersion: String) {
        self.readers = readers
        self.actions = actions
        self.agentVersion = agentVersion
    }

    public func handle(_ request: Envelope, from console: PairedConsole, settings: RemoteSettings) async
        -> (response: Envelope, record: ActionRecord?) {
        guard request.version == RemoteProtocolVersion.current else {
            return (request.failure(RemoteError(.unsupportedVersion, "This Mac speaks protocol version \(RemoteProtocolVersion.current).")), nil)
        }
        guard request.kind == .request else {
            return (request.failure(RemoteError(.invalidPayload, "Only requests are accepted.")), nil)
        }
        if request.operation.isAction {
            return await act(request, console: console, settings: settings)
        }
        do {
            return (try await read(request, console: console, settings: settings), nil)
        } catch let error as RemoteError {
            return (request.failure(error), nil)
        } catch {
            return (request.failure(RemoteError(.unavailable, error.localizedDescription)), nil)
        }
    }

    private func read(_ request: Envelope, console: PairedConsole, settings: RemoteSettings) async throws -> Envelope {
        switch request.operation {
        case .capabilities:
            return try request.response(Capabilities(agentVersion: agentVersion, device: readers.device(),
                                                     operations: Operation.reads + Operation.actions,
                                                     actionsAllowed: settings.allowActions && console.role.mayAct))
        case .deviceInfo: return try request.response(readers.device())
        case .cpuTopology: return try request.response(readers.cpuTopology())
        case .cpuSnapshot: return try request.response(try readers.cpuSnapshot())
        case .memoryStats: return try request.response(try readers.memory())
        case .processUsage: return try request.response(try readers.processUsage())
        case .diskVolumes: return try request.response(try readers.volumes())
        case .networkCounters: return try request.response(try readers.networkCounters())
        case .networkSnapshot: return try request.response(try await readers.networkSnapshot())
        case .ports: return try request.response(try await readers.ports())
        case .processes: return try request.response(try await readers.processes())
        case .sleep: return try request.response(try await readers.sleep())
        case .dnsConfiguration: return try request.response(try await readers.dnsConfiguration())
        case .dnsProbe:
            let body = try request.body(DNSProbeRequest.self)
            guard NetworkInput.isHostname(body.name) else { throw RemoteError(.invalidPayload, "That is not a host name.") }
            let configuration = try await readers.dnsConfiguration()
            let servers = Set((configuration.resolvers + configuration.scopedResolvers).flatMap(\.nameservers))
            guard servers.contains(body.server) else {
                throw RemoteError(.notPermitted, "This Mac only tests the DNS servers it is configured to use.")
            }
            return try request.response(try await readers.dnsProbe(body.server, body.name))
        default:
            throw RemoteError(.unknownOperation, "This Mac does not know \(request.operation.rawValue).")
        }
    }

    private func act(_ request: Envelope, console: PairedConsole, settings: RemoteSettings) async -> (response: Envelope, record: ActionRecord?) {
        let event: String
        do {
            switch request.operation {
            case .freePort:
                let body = try request.body(FreePortRequest.self)
                event = "\(body.force ? "Force-free" : "Free") port \(body.port.port) (\(body.port.processName), PID \(body.port.pid))"
                if let refusal = refusal(console: console, settings: settings) {
                    return (request.failure(refusal), ActionRecord(event: event, outcome: "Refused: \(refusal.message)"))
                }
                let result = await actions.freePort(body.port, body.force)
                return (try request.response(ActionResult(result: result)), ActionRecord(event: event, outcome: Self.outcome(result)))
            case .quitProcess:
                let body = try request.body(QuitProcessRequest.self)
                event = "\(body.force ? "Force quit" : "Quit") \(body.process.name) (PID \(body.process.pid))"
                if let refusal = refusal(console: console, settings: settings) {
                    return (request.failure(refusal), ActionRecord(event: event, outcome: "Refused: \(refusal.message)"))
                }
                let result = await actions.quitProcess(body.process, body.force)
                return (try request.response(ActionResult(result: result)), ActionRecord(event: event, outcome: Self.outcome(result)))
            default:
                return (request.failure(RemoteError(.unknownOperation, "This Mac does not know \(request.operation.rawValue).")), nil)
            }
        } catch let error as RemoteError {
            return (request.failure(error), nil)
        } catch {
            return (request.failure(RemoteError(.invalidPayload, error.localizedDescription)), nil)
        }
    }

    private func refusal(console: PairedConsole, settings: RemoteSettings) -> RemoteError? {
        guard console.role.mayAct else { return RemoteError(.notPermitted, "This console is paired view-only.") }
        guard settings.allowActions else { return RemoteError(.actionsDisabled, "Actions are turned off on this Mac.") }
        return nil
    }

    static func outcome(_ result: TerminationResult) -> String {
        switch result {
        case .terminated: return "Done"
        case .alreadyExited: return "Already exited"
        case .resourceAlreadyReleased: return "Already released"
        case .permissionDenied: return "Refused: permission denied"
        case .targetChanged: return "Refused: the process changed"
        case .stillRunning: return "Still running"
        case .failed(let message): return "Failed: \(message)"
        }
    }
}
