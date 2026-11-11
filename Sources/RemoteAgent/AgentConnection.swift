import Foundation
import RemoteCrypto
import RemoteProtocol

/// One console's connection to this Mac, independent of the transport (TCP on the local network, a stream through the
/// relay): feed it the bytes that arrive with `receive`, and it sends frames back through `send`. A device of this
/// Mac's account authenticates with the handshake, then sends encrypted requests. Anything unexpected ends the connection.
public actor AgentConnection {
    private enum Phase {
        case awaitingHello
        case awaitingFinish(MacHandshake)
        case open(SecureChannel, console: PublicIdentity, chain: WorkspaceChain)
        case closed
    }

    public nonisolated let id = UUID()
    private let state: AgentState
    private let handler: RequestHandler
    private let send: @Sendable (Data) async -> Void
    private let onClose: @Sendable () async -> Void
    private var reader = Framing.Reader()
    private var phase = Phase.awaitingHello

    public init(state: AgentState, handler: RequestHandler, send: @escaping @Sendable (Data) async -> Void,
                onClose: @escaping @Sendable () async -> Void) {
        self.state = state
        self.handler = handler
        self.send = send
        self.onClose = onClose
    }

    /// Call once, before the first `receive`.
    public func start() async {
        await state.register(self)
    }

    public func receive(_ bytes: Data) async {
        guard !isClosed else { return }
        do {
            for frame in try reader.append(bytes) {
                guard !isClosed else { return }
                try await handle(try WireMessage.decoded(from: frame))
            }
        } catch {
            await close(reason: Self.reason(for: error))
        }
    }

    /// Sends `refused` (when there is a reason) and ends the connection.
    public func close(reason: String?) async {
        guard !isClosed else { return }
        phase = .closed
        if let reason { await write(.refused(reason)) }
        await state.unregister(id)
        await onClose()
    }

    /// The transport went away.
    public func disconnected() async {
        await close(reason: nil)
    }

    private var isClosed: Bool {
        if case .closed = phase { return true }
        return false
    }

    private func handle(_ message: WireMessage) async throws {
        guard await state.settings.isEnabled else { throw AgentRefusal("Remote management is turned off on this Mac.") }
        switch (phase, message) {
        case (.awaitingHello, .hello(let hello)):
            guard await state.membership != nil else {
                throw AgentRefusal("This Mac is not in a MacPeek Remote account. On this Mac, choose Add to my account in MacPeek ▸ Settings ▸ Remote management.")
            }
            var handshake = MacHandshake(identity: state.identity)
            let reply = try handshake.reply(to: hello)
            phase = .awaitingFinish(handshake)
            await write(.reply(reply))

        case (.awaitingFinish(let handshake), .finish(let finish)):
            let membership = await state.membership
            let (channel, console, chain) = try handshake.accept(finish, trustChain: { identity, chain -> Bool in
                // Only a device whose chain leads to the account key this Mac pinned.
                guard let chain else { return false }
                return membership?.role(for: identity, chain: chain) != nil
            })
            guard let chain else { throw SessionError.untrustedPeer }
            guard advance(to: .open(channel, console: console, chain: chain)) else { return }
            await state.consoleConnected(connectionID: id, console: console, chain: chain)

        case (.open(var channel, let console, let chain), .sealed(let frame)):
            let request = try JSONDecoder().decode(Envelope.self, from: try channel.open(frame))
            // Looked up again for every request, so a revocation or a changed role takes effect at once.
            guard let device = await state.authorize(console, chain: chain) else {
                throw AgentRefusal("This device was removed from the account.")
            }
            guard !isClosed else { return }
            let response: Envelope
            if Operation.workspace.contains(request.operation), request.kind == .request,
               request.version == RemoteProtocolVersion.current {
                response = await state.handleWorkspace(request, from: device)
            } else {
                let (answer, record) = await handler.handle(request, from: device, settings: await state.settings)
                if let record { await state.recordAction(by: device, event: record.event, outcome: record.outcome) }
                response = answer
            }
            let sealed = try channel.seal(try JSONEncoder().encode(response))
            // Closed while the request ran (revoked, turned off): do not reopen the connection or answer.
            guard advance(to: .open(channel, console: console, chain: chain)) else { return }
            await write(.sealed(sealed))

        default:
            throw SessionError.unexpectedMessage
        }
    }

    /// Moves to `next` unless the connection was closed while this one was waiting; false means it was.
    private func advance(to next: Phase) -> Bool {
        guard !isClosed else { return false }
        phase = next
        return true
    }

    private func write(_ message: WireMessage) async {
        guard let data = try? message.encoded() else { return }
        await send(Framing.frame(data))
    }

    static func reason(for error: Error) -> String {
        switch error {
        case let refusal as AgentRefusal: return refusal.message
        case SessionError.unsupportedVersion:
            return "This Mac's MacPeek speaks a different protocol version. Update both apps."
        case SessionError.untrustedPeer: return "This device is not in this Mac's MacPeek Remote account."
        case Framing.Error.frameTooLarge: return "A message was too large."
        default: return "The connection was closed because of an unexpected message."
        }
    }
}

struct AgentRefusal: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

extension AgentRefusal: LocalizedError {
    var errorDescription: String? { message }
}
