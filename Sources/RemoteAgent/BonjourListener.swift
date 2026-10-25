#if canImport(Network)
import Foundation
import Network

/// Listens on the local network and advertises this Mac as `_macpeek._tcp` so consoles can find it. Only runs while
/// Remote management is on; `stop()` closes the listener and every connection.
///
/// The transport is plain TCP: pairing, the handshake and every frame after it are protected end to end by
/// RemoteCrypto, the same way they will be through the relay.
public final class BonjourListener: @unchecked Sendable {
    public static let serviceType = "_macpeek._tcp"

    public enum Status: Equatable, Sendable {
        case stopped
        case starting
        case listening(port: UInt16)
        case failed(String)
    }

    private let state: AgentState
    private let handler: RequestHandler
    private let name: String
    private let queue = DispatchQueue(label: "MacPeek.RemoteAgent.Listener")
    private let onStatus: @Sendable (Status) -> Void
    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]

    public init(state: AgentState, handler: RequestHandler, name: String, onStatus: @escaping @Sendable (Status) -> Void) {
        self.state = state
        self.handler = handler
        self.name = name
        self.onStatus = onStatus
    }

    public func start() {
        queue.async { [self] in
            guard listener == nil else { return }
            do {
                let parameters = NWParameters.tcp
                parameters.includePeerToPeer = false
                let listener = try NWListener(using: parameters)
                listener.service = NWListener.Service(name: name, type: Self.serviceType)
                listener.stateUpdateHandler = { [weak self, weak listener] state in
                    guard let self else { return }
                    switch state {
                    case .ready: self.onStatus(.listening(port: listener?.port?.rawValue ?? 0))
                    case .failed(let error): self.onStatus(.failed(error.localizedDescription))
                    case .cancelled: self.onStatus(.stopped)
                    default: break
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
                self.listener = listener
                onStatus(.starting)
                listener.start(queue: queue)
            } catch {
                onStatus(.failed(error.localizedDescription))
            }
        }
    }

    public func stop() {
        queue.async { [self] in
            listener?.cancel()
            listener = nil
            for connection in connections.values { connection.cancel() }
            connections.removeAll()
        }
    }

    private func accept(_ nwConnection: NWConnection) {
        let agent = AgentConnection(
            state: state, handler: handler,
            send: { data in
                await withCheckedContinuation { continuation in
                    nwConnection.send(content: data, completion: .contentProcessed { _ in continuation.resume() })
                }
            },
            onClose: { nwConnection.cancel() })
        // Bytes are handed to the agent in order, one chunk at a time.
        let (chunks, continuation) = AsyncStream<Data>.makeStream()
        let id = agent.id
        connections[id] = nwConnection
        nwConnection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                continuation.finish()
                self?.queue.async { self?.connections[id] = nil }
            default: break
            }
        }
        Task {
            await agent.start()
            for await chunk in chunks { await agent.receive(chunk) }
            await agent.disconnected()
        }
        receive(on: nwConnection, into: continuation)
        nwConnection.start(queue: queue)
    }

    private func receive(on connection: NWConnection, into continuation: AsyncStream<Data>.Continuation) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            if let data, !data.isEmpty { continuation.yield(data) }
            if isComplete || error != nil {
                continuation.finish()
                connection.cancel()
            } else {
                self?.receive(on: connection, into: continuation)
            }
        }
    }
}
#endif
