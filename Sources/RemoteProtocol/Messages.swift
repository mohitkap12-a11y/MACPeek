import Foundation
import MacPeekCore
import PortPeekKit
import ProcessPeekKit
import RemoteCrypto

/// Version 1 of what a MacPeek Remote console and a Mac's agent say to each other.
public enum RemoteProtocolVersion {
    public static let current = 1
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
    public static let freePort: Operation = "ports.free"
    public static let quitProcess: Operation = "processes.quit"

    public static let reads: [Operation] = [.capabilities, .deviceInfo, .cpuTopology, .cpuSnapshot, .memoryStats, .processUsage,
                                            .diskVolumes, .networkCounters, .networkSnapshot, .ports, .processes, .sleep,
                                            .dnsConfiguration, .dnsProbe]
    public static let actions: [Operation] = [.freePort, .quitProcess]

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
