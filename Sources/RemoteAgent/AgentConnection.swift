import Foundation
import RemoteCrypto
import RemoteProtocol

/// One console's connection to this Mac, independent of the transport (TCP on the local network, a stream through the
/// relay): feed it the bytes that arrive with `receive`, and it sends frames back through `send`. A device of this
/// Mac's account authenticates with the handshake, then sends encrypted requests. Anything unexpected ends the connection.
///
/// A connection can instead become a tunnel (`tunnel.open`, Pro): from then on it carries only the bytes of one TCP
/// connection to a port on this Mac's 127.0.0.1, sealed frame by frame (`TunnelFraming`), until either side closes.
public actor AgentConnection {
    private enum Phase {
        case awaitingHello
        case awaitingFinish(MacHandshake)
        case open(SecureChannel, console: PublicIdentity, chain: WorkspaceChain)
        case tunnel(console: PublicIdentity, chain: WorkspaceChain)
        case closed
    }

    /// The bytes of an open tunnel and what it sealed, kept apart from the phase so both directions can use the channel.
    private struct TunnelState {
        var channel: SecureChannel
        let socket: TunnelSocket
        let port: Int
        let consoleName: String
        let fingerprint: String
        let openedAt: Date
        var bytesIn = 0
        var bytesOut = 0
    }

    public nonisolated let id = UUID()
    private let state: AgentState
    private let handler: RequestHandler
    private let send: @Sendable (Data) async -> Void
    private let onClose: @Sendable () async -> Void
    /// Whether this route carries tunnels: the local network does; a relay stream only when the relay marked it as a
    /// tunnel stream (the relay checks the plan includes Pro and the account's tunnel allowance).
    private let routeAllowsTunnels: Bool
    private let viaRelay: Bool
    private var reader = Framing.Reader()
    private var phase = Phase.awaitingHello
    private var tunnel: TunnelState?
    private var pump: Task<Void, Never>?

    public init(state: AgentState, handler: RequestHandler, send: @escaping @Sendable (Data) async -> Void,
                onClose: @escaping @Sendable () async -> Void, allowsTunnels: Bool = true, viaRelay: Bool = false) {
        self.state = state
        self.handler = handler
        self.send = send
        self.onClose = onClose
        routeAllowsTunnels = allowsTunnels
        self.viaRelay = viaRelay
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
                if case .tunnel = phase {
                    try await tunnelFrame(frame)
                } else {
                    try await handle(try WireMessage.decoded(from: frame))
                }
            }
        } catch {
            await close(reason: Self.reason(for: error))
        }
    }

    /// Sends `refused` (when there is a reason) and ends the connection. A tunnel just ends: its console reads bytes, not
    /// messages, by then.
    public func close(reason: String?) async {
        guard !isClosed else { return }
        let wasTunnel: Bool
        if case .tunnel = phase { wasTunnel = true } else { wasTunnel = false }
        phase = .closed
        if let reason, !wasTunnel { await write(.refused(reason)) }
        await endTunnel(reason: reason)
        await state.unregister(id)
        await onClose()
    }

    /// The transport went away.
    public func disconnected() async {
        await close(reason: nil)
    }

    /// The tunnel's port, while this connection is one.
    var tunnelPort: Int? { tunnel?.port }

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
            // Capabilities report what the person allows whatever the route, so a console connected through the relay
            // knows it can open tunnels: each opens its own tunnel stream, and `openTunnel` refuses a plain relay stream.
            let settings = await state.settings
            if request.operation == .tunnelOpen {
                try await openTunnel(request, channel: channel, console: console, chain: chain, device: device, settings: settings)
                return
            }
            let response: Envelope
            if Operation.workspace.contains(request.operation), request.kind == .request,
               request.version == RemoteProtocolVersion.current {
                response = await state.handleWorkspace(request, from: device)
            } else {
                let (answer, record) = await handler.handle(request, from: device, settings: settings)
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

    // MARK: Tunnels

    /// `tunnel.open`: checks the device may act, the route carries tunnels and the person at the Mac allows the port,
    /// connects to it on 127.0.0.1, answers, and from then on carries its bytes. A refusal is an ordinary error answer
    /// and the connection stays as it was.
    private func openTunnel(_ request: Envelope, channel: SecureChannel, console: PublicIdentity, chain: WorkspaceChain,
                            device: PairedConsole, settings: RemoteSettings) async throws {
        var channel = channel
        func answer(_ response: Envelope) async throws {
            let sealed = try channel.seal(try JSONEncoder().encode(response))
            guard advance(to: .open(channel, console: console, chain: chain)) else { return }
            await write(.sealed(sealed))
        }
        func refuse(_ error: RemoteError, port: Int?) async throws {
            if let port {
                await state.recordAction(by: device, event: "Open tunnel to port \(port)", outcome: "Refused: \(error.message)")
            }
            try await answer(request.failure(error))
        }
        guard request.kind == .request, request.version == RemoteProtocolVersion.current else {
            return try await refuse(RemoteError(.invalidPayload, "Only requests are accepted."), port: nil)
        }
        let body: TunnelOpenRequest
        do { body = try request.body(TunnelOpenRequest.self) } catch let error as RemoteError { return try await refuse(error, port: nil) }
        let port = body.port
        guard TunnelPolicy.isPort(port) else { return try await refuse(RemoteError(.invalidPayload, "That is not a port."), port: nil) }
        guard device.role.mayAct else {
            return try await refuse(RemoteError(.notPermitted, "This device has view-only access to this Mac, so it cannot open tunnels."), port: port)
        }
        guard routeAllowsTunnels else {
            return try await refuse(RemoteError(.notPermitted, "Tunnels through MacPeek's relay are part of MacPeek Remote Pro."), port: port)
        }
        guard settings.tunnels.allows(port) else {
            let reason = settings.tunnels.isOn
                ? "This Mac does not allow tunnels to port \(port). Its person can change that in MacPeek ▸ Settings ▸ Remote management."
                : "Tunnels are turned off on this Mac. Its person can turn on Allow tunnels in MacPeek ▸ Settings ▸ Remote management."
            return try await refuse(RemoteError(.notPermitted, reason), port: port)
        }
        let socket: TunnelSocket
        do {
            socket = try await handler.tunnelDialer.dial(port: port)
        } catch {
            return try await refuse(RemoteError(.unavailable, "Nothing on this Mac accepts connections on port \(port)."), port: port)
        }
        // Closed while connecting (revoked, turned off): drop the socket.
        guard case .open = phase else {
            socket.close()
            return
        }
        // The person may have narrowed Allow tunnels, or lowered the account's access, while this connected: check again
        // now, since a change made then found no open tunnel to close.
        let now = await state.settings
        guard now.isEnabled, now.tunnels.allows(port), await state.authorize(console, chain: chain)?.role.mayAct == true else {
            socket.close()
            return try await refuse(RemoteError(.notPermitted, "Tunnels to port \(port) were turned off on this Mac while it connected."), port: port)
        }
        guard case .open = phase else {
            socket.close()
            return
        }
        let sealed = try channel.seal(try JSONEncoder().encode(try request.response(TunnelOpenResponse(port: port))))
        phase = .tunnel(console: console, chain: chain)
        tunnel = TunnelState(channel: channel, socket: socket, port: port, consoleName: device.identity.name,
                             fingerprint: device.identity.fingerprint, openedAt: Date())
        await write(.sealed(sealed))
        await state.tunnelOpened(OpenTunnel(id: id, port: port, consoleName: device.identity.name, viaRelay: viaRelay, openedAt: Date()),
                                 by: device)
        pump = Task { [weak self] in await self?.pumpFromSocket(socket) }
    }

    /// A frame from the console while this is a tunnel: a sealed piece of the stream, or an empty one for its end.
    private func tunnelFrame(_ frame: Data) async throws {
        guard var current = tunnel else { throw SessionError.unexpectedMessage }
        let bytes = try current.channel.open(frame)
        tunnel = current
        guard !bytes.isEmpty else {
            await close(reason: nil)
            return
        }
        tunnel?.bytesIn += bytes.count
        do {
            try await current.socket.send(bytes)
        } catch {
            await close(reason: nil)
        }
    }

    /// Reads the TCP connection and sends each piece to the console, sealed, in order; its end ends the tunnel.
    private func pumpFromSocket(_ socket: TunnelSocket) async {
        while !Task.isCancelled {
            let piece: Data?
            do { piece = try await socket.receive() } catch { piece = nil }
            guard let piece, !piece.isEmpty else {
                await sendTunnel(Data())
                await close(reason: nil)
                return
            }
            var offset = piece.startIndex
            while offset < piece.endIndex {
                let end = min(offset + TunnelFraming.chunkSize, piece.endIndex)
                guard await sendTunnel(piece.subdata(in: offset..<end)) else { return }
                offset = end
            }
        }
    }

    /// Seals and sends one piece of the stream; false once the tunnel has ended.
    @discardableResult
    private func sendTunnel(_ bytes: Data) async -> Bool {
        guard case .tunnel = phase, var current = tunnel, let sealed = try? current.channel.seal(bytes) else { return false }
        current.bytesOut += bytes.count
        tunnel = current
        await send(Framing.frame(sealed))
        return true
    }

    /// Closes the TCP connection and records how the tunnel went.
    private func endTunnel(reason: String?) async {
        pump?.cancel()
        pump = nil
        guard let ended = tunnel else { return }
        tunnel = nil
        ended.socket.close()
        await state.tunnelClosed(id: id, port: ended.port, consoleName: ended.consoleName, fingerprint: ended.fingerprint,
                                 openedAt: ended.openedAt, bytesIn: ended.bytesIn, bytesOut: ended.bytesOut, reason: reason)
    }

    // MARK: Writing

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
