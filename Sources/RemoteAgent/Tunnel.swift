import Foundation
import RemoteProtocol
#if canImport(Network)
import Network
#endif

// Tunnels (Pro, macpeek-remote docs/PRO.md §5): a console's connection that asked `tunnel.open` carries the bytes of
// one TCP connection to a port on this Mac's own 127.0.0.1, end-to-end encrypted, on the local network or through the
// relay. What may be reached is the person's choice ("Allow tunnels", `TunnelPolicy`); nothing else on the network
// can be reached through it.

/// One TCP connection on this Mac, for a tunnel. `receive` returns nil once the other end closed it.
public protocol TunnelSocket: AnyObject, Sendable {
    func send(_ data: Data) async throws
    func receive() async throws -> Data?
    func close()
}

/// Connects to a port on this Mac's 127.0.0.1.
public protocol TunnelDialing: Sendable {
    func dial(port: Int) async throws -> TunnelSocket
}

/// Why a tunnel could not be opened.
public struct TunnelUnavailable: Error, Equatable {
    public let port: Int
    public init(port: Int) { self.port = port }
}

/// An open tunnel, for the person at the Mac: where it goes and who opened it.
public struct OpenTunnel: Identifiable, Equatable, Sendable {
    /// The connection's id: closing it closes the tunnel.
    public let id: UUID
    public let port: Int
    public let consoleName: String
    public let viaRelay: Bool
    public let openedAt: Date
}

/// Where tunnels cannot be made (Linux, where only the core logic is built and tested).
public struct UnavailableTunnelDialer: TunnelDialing {
    public init() {}
    public func dial(port: Int) async throws -> TunnelSocket { throw TunnelUnavailable(port: port) }
}

#if canImport(Network)
/// Tunnels to 127.0.0.1 with Network.framework. Only the loopback address is ever dialled.
public struct LoopbackTunnelDialer: TunnelDialing {
    public init() {}

    public func dial(port: Int) async throws -> TunnelSocket {
        guard TunnelPolicy.isPort(port), let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { throw TunnelUnavailable(port: port) }
        let socket = LoopbackTunnelSocket(connection: NWConnection(host: .ipv4(.loopback), port: nwPort, using: .tcp))
        try await socket.start(port: port)
        return socket
    }
}

final class LoopbackTunnelSocket: TunnelSocket, @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "app.macpeek.remote.tunnel")

    init(connection: NWConnection) {
        self.connection = connection
    }

    /// Waits until the connection is ready, failing at once when nothing listens there (refused) and after 5 seconds
    /// otherwise.
    func start(port: Int) async throws {
        let connection = connection
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = OnceGate()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: gate.run { continuation.resume() }
                case .failed, .cancelled: gate.run { continuation.resume(throwing: TunnelUnavailable(port: port)) }
                case .waiting:
                    // Loopback never waits for a path: waiting means refused.
                    gate.run {
                        connection.cancel()
                        continuation.resume(throwing: TunnelUnavailable(port: port))
                    }
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 5) {
                gate.run {
                    connection.cancel()
                    continuation.resume(throwing: TunnelUnavailable(port: port))
                }
            }
        }
    }

    func send(_ data: Data) async throws {
        let connection = connection
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }

    func receive() async throws -> Data? {
        let connection = connection
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: TunnelFraming.chunkSize) { data, _, _, error in
                if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    // No data and no error: the other end closed its side (`isComplete`).
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func close() {
        connection.cancel()
    }
}

/// Lets the first of several callbacks resume a continuation.
private final class OnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ body: () -> Void) {
        lock.lock()
        let first = !done
        done = true
        lock.unlock()
        if first { body() }
    }
}
#endif
