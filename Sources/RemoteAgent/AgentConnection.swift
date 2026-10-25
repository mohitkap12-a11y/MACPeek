import Foundation
import RemoteCrypto
import RemoteProtocol

/// One console's connection to this Mac, independent of the transport: feed it the bytes that arrive with `receive`,
/// and it sends frames back through `send`. It either pairs (when a code is on screen) or authenticates a paired
/// console, then answers encrypted requests. Anything unexpected ends the connection.
public actor AgentConnection {
    private enum Phase {
        case awaitingFirstMessage
        case pairingAwaitingReveal(MacPairing)
        /// Both people must confirm the words: the console sends Confirm, the person here picks a role.
        case pairingAwaitingConfirmations(MacPairing, console: PublicIdentity?, role: ConsoleRole?)
        case awaitingFinish(MacHandshake)
        case open(SecureChannel, console: PublicIdentity)
        case closed
    }

    public nonisolated let id = UUID()
    private let state: AgentState
    private let handler: RequestHandler
    private let send: @Sendable (Data) async -> Void
    private let onClose: @Sendable () async -> Void
    private var reader = Framing.Reader()
    private var phase = Phase.awaitingFirstMessage

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
        if case .pairingAwaitingConfirmations = phase {
            await state.pairingEnded(connectionID: id, declined: false)
        }
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
        case (.awaitingFirstMessage, .pairStart(let start)):
            guard var pairing = await state.beginPairing() else {
                throw AgentRefusal("This Mac is not showing a pairing code.")
            }
            do {
                let accept = try pairing.accept(start)
                phase = .pairingAwaitingReveal(pairing)
                await write(.pairAccept(accept))
            } catch let error as PairingError where error == .codeExpired {
                await state.recordFailedPairing(error)
                throw error
            }

        case (.pairingAwaitingReveal(var pairing), .pairReveal(let reveal)):
            do {
                let words = try pairing.words(after: reveal)
                phase = .pairingAwaitingConfirmations(pairing, console: nil, role: nil)
                await state.pairingNeedsConfirmation(connectionID: id, words: words)
            } catch let error as PairingError where error == .wrongCode || error == .codeExpired {
                await state.recordFailedPairing(error)
                throw error
            }

        case (.pairingAwaitingConfirmations(let pairing, nil, let role), .pairConfirm(let confirm)):
            let console = try pairing.consoleIdentity(from: confirm)
            phase = .pairingAwaitingConfirmations(pairing, console: console, role: role)
            await state.pairingConsoleConfirmed(connectionID: id, console: console)
            try await finishPairingIfConfirmed()

        case (.awaitingFirstMessage, .hello(let hello)):
            var handshake = MacHandshake(identity: state.identity)
            let reply = try handshake.reply(to: hello)
            phase = .awaitingFinish(handshake)
            await write(.reply(reply))

        case (.awaitingFinish(let handshake), .finish(let finish)):
            let consoles = await state.consoles
            let (channel, console) = try handshake.accept(finish) { identity in
                consoles.contains { $0.identity.isSameDevice(as: identity) }
            }
            phase = .open(channel, console: console)
            await state.consoleConnected(connectionID: id, console: console)

        case (.open(var channel, let console), .sealed(let frame)):
            let request = try JSONDecoder().decode(Envelope.self, from: try channel.open(frame))
            // Looked up again for every request, so a revoked console or a changed role takes effect at once.
            guard let paired = await state.pairedConsole(console) else { throw AgentRefusal("This console's pairing was revoked.") }
            let (response, record) = await handler.handle(request, from: paired, settings: await state.settings)
            if let record { await state.recordAction(by: paired, event: record.event, outcome: record.outcome) }
            let sealed = try channel.seal(try JSONEncoder().encode(response))
            phase = .open(channel, console: console)
            await write(.sealed(sealed))

        default:
            throw SessionError.unexpectedMessage
        }
    }

    /// The person at this Mac decided; `role` nil means the words did not match.
    func localDecision(_ role: ConsoleRole?) async {
        guard case .pairingAwaitingConfirmations(let pairing, let console, nil) = phase else { return }
        guard let role else {
            await state.pairingEnded(connectionID: id, declined: true)
            phase = .awaitingFirstMessage
            await close(reason: "The words were not confirmed on this Mac.")
            return
        }
        phase = .pairingAwaitingConfirmations(pairing, console: console, role: role)
        do {
            try await finishPairingIfConfirmed()
        } catch {
            await close(reason: Self.reason(for: error))
        }
    }

    private func finishPairingIfConfirmed() async throws {
        guard case .pairingAwaitingConfirmations(let pairing, let console?, let role?) = phase else { return }
        let confirm = try pairing.confirm()
        await state.completePairing(connectionID: id, console: console, role: role)
        // The console may go straight on to a handshake on this connection.
        phase = .awaitingFirstMessage
        await write(.pairConfirm(confirm))
    }

    private func write(_ message: WireMessage) async {
        guard let data = try? message.encoded() else { return }
        await send(Framing.frame(data))
    }

    static func reason(for error: Error) -> String {
        switch error {
        case let refusal as AgentRefusal: return refusal.message
        case PairingError.wrongCode: return "The pairing code was wrong."
        case PairingError.codeExpired: return "The pairing code has expired. Show a new one on the Mac."
        case PairingError.unsupportedVersion, SessionError.unsupportedVersion:
            return "This Mac's MacPeek speaks a different protocol version. Update both apps."
        case SessionError.untrustedPeer: return "This console is not paired with this Mac."
        case Framing.Error.frameTooLarge: return "A message was too large."
        default: return "The connection was closed because of an unexpected message."
        }
    }
}

struct AgentRefusal: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
