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
import USBPeekKit
import ContainerPeekKit
import GPUPeekKit
import ModelPeekKit
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
    public var networkExtras: @Sendable () async throws -> NetExtras
    public var dnsOverrides: @Sendable () async throws -> DNSOverrides
    public var bluetooth: @Sendable () async throws -> BluetoothReport
    public var processOrigin: @Sendable (_ process: ProcessEntry, _ snapshot: ProcessSnapshot) async throws -> ProcessOrigin
    public var openFiles: @Sendable (_ process: ProcessEntry) async throws -> OpenFilesReport
    public var containers: @Sendable () async throws -> ContainerSnapshot
    public var gpu: @Sendable () async throws -> GPUSnapshot
    public var models: @Sendable () async throws -> ModelSnapshot
    public var volumeIO: @Sendable () throws -> [VolumeIOCounters]

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
                },
                networkExtras: @escaping @Sendable () async throws -> NetExtras = { throw RemoteError(.unavailable, "This Mac does not report that.") },
                dnsOverrides: @escaping @Sendable () async throws -> DNSOverrides = { throw RemoteError(.unavailable, "This Mac does not report that.") },
                bluetooth: @escaping @Sendable () async throws -> BluetoothReport = { throw RemoteError(.unavailable, "This Mac does not report that.") },
                processOrigin: @escaping @Sendable (ProcessEntry, ProcessSnapshot) async throws -> ProcessOrigin = { _, _ in
                    throw RemoteError(.unavailable, "This Mac does not report that.")
                },
                openFiles: @escaping @Sendable (ProcessEntry) async throws -> OpenFilesReport = { _ in
                    throw RemoteError(.unavailable, "This Mac does not report that.")
                },
                containers: @escaping @Sendable () async throws -> ContainerSnapshot = { throw RemoteError(.unavailable, "This Mac does not report that.") },
                gpu: @escaping @Sendable () async throws -> GPUSnapshot = { throw RemoteError(.unavailable, "This Mac does not report that.") },
                models: @escaping @Sendable () async throws -> ModelSnapshot = { throw RemoteError(.unavailable, "This Mac does not report that.") },
                volumeIO: @escaping @Sendable () throws -> [VolumeIOCounters] = { throw RemoteError(.unavailable, "This Mac does not report that.") }) {
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
        self.networkExtras = networkExtras
        self.dnsOverrides = dnsOverrides
        self.bluetooth = bluetooth
        self.processOrigin = processOrigin
        self.openFiles = openFiles
        self.containers = containers
        self.gpu = gpu
        self.models = models
        self.volumeIO = volumeIO
    }

    public static func system() -> AgentReaders {
        let cpu = SystemCPUReader(), memory = SystemMemoryReader(), usage = SystemProcessUsageReader()
        let volumes = SystemVolumeCapacityReader(), volumeIO = SystemVolumeIOReader(), counters = SystemInterfaceCountersReader(), network = SystemNetworkReader()
        let ports = PortService(), processes = PSProcessLister(), sleep = PMSetSleepReader(), device = SystemDeviceInfoReader()
        let dns = SystemDNSReader()
        let overrides = FileDNSOverridesReader(), bluetooth = SystemBluetoothReader(), insight = SystemProcessInsightReader()
        let containers = IntervalSampler<ProcessUsageSnapshot?, ContainerSnapshot>(initial: nil) { previous, interval in
            try await SystemContainerReader(usage: usage).snapshot(previous: previous, interval: interval)
        }
        let gpu = IntervalSampler<[GPUClient]?, GPUSnapshot>(initial: nil) { previous, interval in
            try await SystemGPUReader(power: GPUPowerShared.sampler, deviceFacts: GPUPowerShared.deviceFacts).snapshot(previousClients: previous, interval: interval)
        }
        let models = IntervalSampler<ModelSamplingState?, ModelSnapshot>(initial: nil) { previous, _ in
            let (snapshot, state) = try await SystemModelReader(usage: usage, gpu: SystemGPUReader()).snapshot(previous: previous)
            return (snapshot, state)
        }
        return AgentReaders(device: { device.read() }, cpuTopology: { cpu.topology() }, cpuSnapshot: { try cpu.snapshot() },
                            memory: { try memory.read() }, processUsage: { try usage.read(isCancelled: { false }) },
                            volumes: { try volumes.read() }, networkCounters: { try counters.read() },
                            networkSnapshot: { try await network.snapshot() }, ports: { try await ports.scan() },
                            processes: { try await processes.snapshot() }, sleep: { try await sleep.snapshot() },
                            dnsConfiguration: { try await dns.configuration() },
                            dnsProbe: { server, name in try await dns.probe(server: server, name: name) },
                            networkExtras: { try await network.extras(wifiInterface: try? await network.snapshot().primary.flatMap { $0.isWiFi ? $0.name : nil }) },
                            dnsOverrides: { overrides.overrides() }, bluetooth: { try await bluetooth.bluetooth() },
                            processOrigin: { entry, snapshot in await insight.origin(of: entry, in: snapshot) },
                            openFiles: { entry in try await insight.openFiles(of: entry, limit: 300) },
                            containers: { try await containers.read() }, gpu: { try await gpu.read() },
                            models: { try await models.read() }, volumeIO: { try volumeIO.read() })
    }
}

/// How the agent carries out actions. `system()` uses MacPeek's safe-termination services, which re-check the target
/// (same process, still holding the port) before any signal and never escalate to SIGKILL on their own.
public struct AgentActions: Sendable {
    public var freePort: @Sendable (PortInfo, _ force: Bool) async -> TerminationResult
    public var quitProcess: @Sendable (ProcessEntry, _ force: Bool) async -> TerminationResult
    public var containerAction: @Sendable (ContainerAction, ContainerInfo, ContainerEngineKind) async -> ContainerActionResult

    public init(freePort: @escaping @Sendable (PortInfo, Bool) async -> TerminationResult,
                quitProcess: @escaping @Sendable (ProcessEntry, Bool) async -> TerminationResult,
                containerAction: @escaping @Sendable (ContainerAction, ContainerInfo, ContainerEngineKind) async -> ContainerActionResult = { _, _, _ in
                    .failed("This Mac does not manage containers.")
                }) {
        self.freePort = freePort
        self.quitProcess = quitProcess
        self.containerAction = containerAction
    }

    public static func system() -> AgentActions {
        let kill = KillService(discovery: LsofPortDiscovery()), terminator = ProcessTerminator()
        let containers = SystemContainerController()
        return AgentActions(freePort: { port, force in force ? await kill.forceTerminate(port) : await kill.terminate(port) },
                            quitProcess: { entry, force in
                                force ? await terminator.forceTerminate(entry) : await terminator.terminate(entry)
                            },
                            containerAction: { action, container, engine in
                                await containers.perform(action, on: container, engine: engine)
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
            return try request.response(Capabilities(protocolVersion: RemoteProtocolVersion.features, agentVersion: agentVersion,
                                                     device: readers.device(),
                                                     operations: Operation.reads + Operation.actions + Operation.workspace,
                                                     actionsAllowed: settings.allowActions && console.role.mayAct))
        case .deviceInfo: return try request.response(readers.device())
        case .cpuTopology: return try request.response(readers.cpuTopology())
        case .cpuSnapshot: return try request.response(try readers.cpuSnapshot())
        case .memoryStats: return try request.response(try readers.memory())
        case .processUsage: return try request.response(try readers.processUsage())
        case .diskVolumes: return try request.response(try readers.volumes())
        case .diskIO: return try request.response(try readers.volumeIO())
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
        case .networkExtras: return try request.response(try await readers.networkExtras())
        case .dnsOverrides: return try request.response(try await readers.dnsOverrides())
        case .bluetooth: return try request.response(try await readers.bluetooth())
        case .containers: return try request.response(try await readers.containers())
        case .gpu: return try request.response(try await readers.gpu())
        case .models: return try request.response(try await readers.models())
        case .processOrigin, .processOpenFiles:
            let body = try request.body(ProcessRequest.self)
            // Answer only about the process the console saw: the PID must still belong to it (same start time).
            let snapshot = try await readers.processes()
            guard let current = snapshot.entry(pid: body.process.pid),
                  PSProcessLister.sameProcess(current.startTime, body.process.startTime) else {
                throw RemoteError(.unavailable, "That process has exited, or its PID now belongs to a different process.")
            }
            if request.operation == .processOpenFiles { return try request.response(try await readers.openFiles(current)) }
            let origin = try await readers.processOrigin(current, snapshot)
            let advice = KillAdvice.assess(entry: current, snapshot: snapshot, origin: origin, currentUID: Int(getuid()))
            return try request.response(ProcessOriginReport(origin: origin, advice: advice))
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
            case .containerAction:
                let body = try request.body(ContainerActionRequest.self)
                event = "\(body.action.title) container \(body.container.name) (\(body.engine.displayName))"
                if let refusal = refusal(console: console, settings: settings) {
                    return (request.failure(refusal), ActionRecord(event: event, outcome: "Refused: \(refusal.message)"))
                }
                guard ContainerID.isValid(body.container.id) else {
                    return (request.failure(RemoteError(.invalidPayload, "That is not a container ID.")),
                            ActionRecord(event: event, outcome: "Refused: not a container ID"))
                }
                let result = await actions.containerAction(body.action, body.container, body.engine)
                let outcome: String
                switch result {
                case .done: outcome = "Done"
                case .changed(let reason): outcome = "Refused: \(reason)"
                case .failed(let reason): outcome = "Failed: \(reason)"
                }
                return (try request.response(ContainerActionResponse(result: result)), ActionRecord(event: event, outcome: outcome))
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

/// Keeps the previous reading's counters between requests, so a rate (CPU, GPU time, power) can be computed over the
/// interval since the last request from any console.
final class IntervalSampler<State: Sendable, Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var state: State
    private var last: Date?
    private let reading: @Sendable (State, TimeInterval) async throws -> (Value, State)

    init(initial: State, reading: @escaping @Sendable (State, TimeInterval) async throws -> (Value, State)) {
        self.state = initial
        self.reading = reading
    }

    func read() async throws -> Value {
        let now = Date()
        let (previous, interval) = snapshotState(now: now)
        let (value, next) = try await reading(previous, interval)
        store(next, at: now)
        return value
    }

    private func snapshotState(now: Date) -> (State, TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        return (state, last.map { now.timeIntervalSince($0) } ?? 0)
    }

    private func store(_ next: State, at date: Date) {
        lock.lock(); defer { lock.unlock() }
        state = next
        last = date
    }
}

/// One power sampler for the agent, created on first use (it subscribes to macOS's energy counters).
enum GPUPowerShared {
    #if canImport(Darwin)
    static let sampler: PowerSampling? = IOReportPowerSampler()
    #else
    static let sampler: PowerSampling? = nil
    #endif

    /// Metal's facts (family, memory the GPU may use) barely change, so they are re-read at most once a minute; that
    /// still picks up an external GPU attached while the agent runs.
    #if canImport(Metal)
    static let deviceFacts: GPUDeviceFactsReading? = RefreshingDeviceFacts(reader: MetalDeviceFactsReader())
    #else
    static let deviceFacts: GPUDeviceFactsReading? = nil
    #endif
}

/// Reuses a reader's facts for `lifetime` seconds before reading them again.
final class RefreshingDeviceFacts: GPUDeviceFactsReading, @unchecked Sendable {
    private let reader: GPUDeviceFactsReading
    private let lifetime: TimeInterval
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var cached: (facts: [GPUDeviceFacts], at: Date)?

    init(reader: GPUDeviceFactsReading, lifetime: TimeInterval = 60, now: @escaping @Sendable () -> Date = { Date() }) {
        self.reader = reader
        self.lifetime = lifetime
        self.now = now
    }

    func facts() -> [GPUDeviceFacts] {
        lock.lock(); defer { lock.unlock() }
        let date = now()
        if let cached, date.timeIntervalSince(cached.at) < lifetime { return cached.facts }
        let facts = reader.facts()
        cached = (facts, date)
        return facts
    }
}
