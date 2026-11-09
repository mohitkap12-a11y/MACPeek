import Foundation
import MacPeekCore
import PortPeekKit
import ProcessPeekKit
import ContainerPeekKit
import RemoteCrypto

/// What a MacPeek Remote console and a Mac's agent say to each other. Version 2 (accounts) only adds: the envelope
/// stays at version 1, so older consoles and agents keep talking, and an agent that speaks version 2 lists the
/// `workspace.*` operations in its capabilities.
public enum RemoteProtocolVersion {
    /// The envelope format, checked on every request.
    public static let current = 1
    /// The newest protocol this agent speaks, reported in `agent.capabilities`.
    public static let features = 2
}

/// What a request asks for. Reads return the Kits' own models (raw counters where a rate needs two readings, so the
/// console computes rates with the same samplers MacPeek uses); actions change something and need permission.
public struct Operation: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }

    public static let capabilities: Operation = "agent.capabilities"
    public static let deviceInfo: Operation = "device.info"
    public static let cpuTopology: Operation = "cpu.topology"
    public static let cpuSnapshot: Operation = "cpu.snapshot"
    public static let memoryStats: Operation = "memory.stats"
    public static let processUsage: Operation = "process.usage"
    public static let diskVolumes: Operation = "disk.volumes"
    public static let networkCounters: Operation = "network.counters"
    public static let networkSnapshot: Operation = "network.snapshot"
    public static let ports: Operation = "ports.list"
    public static let processes: Operation = "processes.list"
    public static let sleep: Operation = "sleep.snapshot"
    public static let dnsConfiguration: Operation = "dns.configuration"
    /// Asks one of the Mac's own DNS servers for a name, as DNSPeek's "Test" does.
    public static let dnsProbe: Operation = "dns.probe"
    /// Proxy, VPN, Tailscale and remembered Wi-Fi networks (NetPeek).
    public static let networkExtras: Operation = "network.extras"
    /// `/etc/hosts` and `/etc/resolver/*` (DNSPeek).
    public static let dnsOverrides: Operation = "dns.overrides"
    /// Bluetooth devices and battery levels (USBPeek).
    public static let bluetooth: Operation = "bluetooth.devices"
    /// How a process was started and whether ending it looks safe (ProcessPeek). Body: `ProcessRequest`.
    public static let processOrigin: Operation = "processes.origin"
    /// A process's open files (ProcessPeek). Body: `ProcessRequest`.
    public static let processOpenFiles: Operation = "processes.openFiles"
    /// Containers, VMs and hypervisor processes (ContainerPeek).
    public static let containers: Operation = "containers.snapshot"
    /// GPU load and memory, GPU clients, and CPU/GPU/Neural Engine power (GPUPeek).
    public static let gpu: Operation = "gpu.snapshot"
    /// Local LLM runners and their loaded models (ModelPeek).
    public static let models: Operation = "models.snapshot"
    public static let freePort: Operation = "ports.free"
    /// Starts, stops, restarts, pauses, resumes or removes one container. Body: `ContainerActionRequest`.
    public static let containerAction: Operation = "containers.action"
    public static let quitProcess: Operation = "processes.quit"
    /// Which workspace (account) this Mac belongs to, its revocation list number and a fresh claim.
    public static let workspaceStatus: Operation = "workspace.status"
    /// Moves a Mac paired with this console alone into the console's workspace ("Move this Mac to your account").
    public static let workspaceAdopt: Operation = "workspace.adopt"
    /// Hands the Mac a newer revocation list for its workspace.
    public static let workspaceRevocations: Operation = "workspace.revocations"

    public static let reads: [Operation] = [.capabilities, .deviceInfo, .cpuTopology, .cpuSnapshot, .memoryStats, .processUsage,
                                            .diskVolumes, .networkCounters, .networkSnapshot, .ports, .processes, .sleep,
                                            .dnsConfiguration, .dnsProbe, .networkExtras, .dnsOverrides, .bluetooth,
                                            .processOrigin, .processOpenFiles, .containers, .gpu, .models]
    public static let actions: [Operation] = [.freePort, .quitProcess, .containerAction]
    /// Account operations: answered by the agent itself, not gated by "Allow actions".
    public static let workspace: [Operation] = [.workspaceStatus, .workspaceAdopt, .workspaceRevocations]

    public var isAction: Bool { Self.actions.contains(self) }
}

/// A request, response or error, sent encrypted inside a `WireMessage.sealed` frame.
public struct Envelope: Equatable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case request, response, error }

    public let version: Int
    /// Chosen by the console; a response or error carries its request's id.
    public let id: String
    public let kind: Kind
    public let operation: Operation
    /// The JSON-encoded body: request arguments, a response value or a `RemoteError`.
    public let payload: Data?

    public init(version: Int = RemoteProtocolVersion.current, id: String, kind: Kind, operation: Operation, payload: Data?) {
        self.version = version
        self.id = id
        self.kind = kind
        self.operation = operation
        self.payload = payload
    }

    public static func request(_ operation: Operation, id: String = UUID().uuidString) -> Envelope {
        Envelope(id: id, kind: .request, operation: operation, payload: nil)
    }

    public static func request<Body: Encodable>(_ operation: Operation, body: Body, id: String = UUID().uuidString) throws -> Envelope {
        Envelope(id: id, kind: .request, operation: operation, payload: try JSONEncoder().encode(body))
    }

    public func response<Body: Encodable>(_ body: Body) throws -> Envelope {
        Envelope(id: id, kind: .response, operation: operation, payload: try JSONEncoder().encode(body))
    }

    public func failure(_ error: RemoteError) -> Envelope {
        Envelope(id: id, kind: .error, operation: operation, payload: try? JSONEncoder().encode(error))
    }

    /// The payload decoded as `Body`; throws `RemoteError.invalidPayload` if it is missing or does not match.
    public func body<Body: Decodable>(_ type: Body.Type) throws -> Body {
        guard let payload, let value = try? JSONDecoder().decode(Body.self, from: payload) else {
            throw RemoteError(.invalidPayload, "The \(operation.rawValue) message is missing its body or it is malformed.")
        }
        return value
    }
}

public struct RemoteError: Error, Equatable, Codable, Sendable {
    public enum Code: String, Codable, Sendable {
        case unsupportedVersion, unknownOperation, invalidPayload
        /// This console is paired view-only.
        case notPermitted
        /// The person at the Mac has switched actions off.
        case actionsDisabled
        /// The Mac could not read what was asked for.
        case unavailable
    }

    public let code: Code
    public let message: String

    public init(_ code: Code, _ message: String) {
        self.code = code
        self.message = message
    }
}

/// What this agent can do, sent in answer to `agent.capabilities`.
public struct Capabilities: Equatable, Codable, Sendable {
    public let protocolVersion: Int
    /// The MacPeek version, e.g. "0.2.0".
    public let agentVersion: String
    public let device: DeviceInfo
    public let operations: [Operation]
    /// Whether this console may run actions right now: it is paired to act and the person at the Mac allows actions.
    public let actionsAllowed: Bool

    public init(protocolVersion: Int = RemoteProtocolVersion.current, agentVersion: String, device: DeviceInfo,
                operations: [Operation], actionsAllowed: Bool) {
        self.protocolVersion = protocolVersion
        self.agentVersion = agentVersion
        self.device = device
        self.operations = operations
        self.actionsAllowed = actionsAllowed
    }
}

/// `dns.probe`: which of the Mac's DNS servers to ask, and for which name. The Mac only asks servers in its own
/// configuration, so a console cannot use it to send queries anywhere else.
public struct DNSProbeRequest: Equatable, Codable, Sendable {
    public let server: String
    public let name: String

    public init(server: String, name: String) {
        self.server = server
        self.name = name
    }
}

/// `workspace.status`, and the answer to `workspace.adopt` and `workspace.revocations`.
public struct WorkspaceStatus: Equatable, Codable, Sendable {
    /// Nil while this Mac trusts only consoles paired with it one by one.
    public let workspaceID: String?
    /// The number of the revocation list the Mac holds; 0 for none.
    public let revocationSequence: Int
    /// A claim signed just now, when the Mac belongs to a workspace.
    public let claim: MacClaim?
    /// Whether this console reached the Mac through the workspace (true) or as a console paired with it alone.
    public let viaWorkspace: Bool

    public init(workspaceID: String?, revocationSequence: Int, claim: MacClaim?, viaWorkspace: Bool) {
        self.workspaceID = workspaceID
        self.revocationSequence = revocationSequence
        self.claim = claim
        self.viaWorkspace = viaWorkspace
    }
}

/// `ports.free`: the port as the console saw it. The Mac re-checks that the same process still owns it before acting.
public struct FreePortRequest: Equatable, Codable, Sendable {
    public let port: PortInfo
    /// SIGKILL instead of SIGTERM. Only ever sent after a graceful attempt, when the person asks for it.
    public let force: Bool

    public init(port: PortInfo, force: Bool = false) {
        self.port = port
        self.force = force
    }
}

/// `processes.quit`: the process as the console saw it. The Mac re-checks its identity before acting.
public struct QuitProcessRequest: Equatable, Codable, Sendable {
    public let process: ProcessEntry
    public let force: Bool

    public init(process: ProcessEntry, force: Bool = false) {
        self.process = process
        self.force = force
    }
}

/// `processes.origin` and `processes.openFiles`: the process as the console saw it. The Mac answers only while that PID
/// still belongs to the same process.
public struct ProcessRequest: Equatable, Codable, Sendable {
    public let process: ProcessEntry

    public init(process: ProcessEntry) {
        self.process = process
    }
}

/// The answer to `processes.origin`.
public struct ProcessOriginReport: Equatable, Codable, Sendable {
    public let origin: ProcessOrigin
    public let advice: KillAdvice

    public init(origin: ProcessOrigin, advice: KillAdvice) {
        self.origin = origin
        self.advice = advice
    }
}

/// `containers.action`: the container as the console saw it. The Mac re-reads it and refuses if it is gone, renamed or
/// in a state where the action does not apply.
public struct ContainerActionRequest: Equatable, Codable, Sendable {
    public let action: ContainerAction
    public let container: ContainerInfo
    public let engine: ContainerEngineKind

    public init(action: ContainerAction, container: ContainerInfo, engine: ContainerEngineKind) {
        self.action = action
        self.container = container
        self.engine = engine
    }
}

public struct ContainerActionResponse: Equatable, Codable, Sendable {
    public let result: ContainerActionResult

    public init(result: ContainerActionResult) {
        self.result = result
    }
}

public struct ActionResult: Equatable, Codable, Sendable {
    public let result: TerminationResult

    public init(result: TerminationResult) {
        self.result = result
    }
}

/// One frame on the connection. Pairing and the handshake travel in the clear (they protect themselves); everything
/// after the handshake is an `Envelope` encrypted with the session's `SecureChannel`.
public enum WireMessage: Equatable, Codable, Sendable {
    case pairStart(PairingMessage.Start)
    case pairAccept(PairingMessage.Accept)
    case pairReveal(PairingMessage.Reveal)
    case pairConfirm(PairingMessage.Confirm)
    case hello(HandshakeMessage.Hello)
    case reply(HandshakeMessage.Reply)
    case finish(HandshakeMessage.Finish)
    case sealed(Data)
    /// The Mac ended the conversation; the reason is for people, not for program logic.
    case refused(String)

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }

    public static func decoded(from data: Data) throws -> WireMessage { try JSONDecoder().decode(WireMessage.self, from: data) }
}

/// Length-prefixed framing for a byte stream: a 4-byte big-endian length, then that many bytes.
public enum Framing {
    /// Larger frames are refused rather than buffered: a process list is well under this.
    public static let maximumFrameSize = 8 * 1024 * 1024

    public enum Error: Swift.Error, Equatable { case frameTooLarge(Int) }

    public static func frame(_ payload: Data) -> Data {
        withUnsafeBytes(of: UInt32(payload.count).bigEndian) { Data($0) } + payload
    }

    /// Collects bytes as they arrive and hands back whole frames.
    public struct Reader: Sendable {
        private var buffer = Data()

        public init() {}

        public mutating func append(_ bytes: Data) throws -> [Data] {
            buffer.append(bytes)
            var frames: [Data] = []
            while buffer.count >= 4 {
                let header = buffer.prefix(4)
                let length = header.reduce(0) { $0 << 8 | Int($1) }
                guard length <= maximumFrameSize else { throw Framing.Error.frameTooLarge(length) }
                guard buffer.count >= 4 + length else { break }
                frames.append(Data(buffer.dropFirst(4).prefix(length)))
                buffer = Data(buffer.dropFirst(4 + length))
            }
            return frames
        }
    }
}
