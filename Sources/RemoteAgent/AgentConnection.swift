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
        /// Both people must confirm the words: the console sends Confirm (with a workspace grant when it is signed in to an
        /// account), the person here picks a role.
        case pairingAwaitingConfirmations(MacPairing, console: PublicIdentity?, grant: WorkspaceGrant?, role: ConsoleRole?)
        /// Both confirmed; the pairing is being stored. Claimed before awaiting, so it is finished only once.
        case finishingPairing
        case awaitingFinish(MacHandshake)
        /// `chain` is set when the console came in through this Mac's workspace.
        case open(SecureChannel, console: PublicIdentity, chain: WorkspaceChain?)
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
        switch phase {
        case .pairingAwaitingConfirmations, .finishingPairing: await state.pairingEnded(connectionID: id, declined: false)
        default: break
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
                guard advance(to: .pairingAwaitingReveal(pairing)) else { return }
                await write(.pairAccept(accept))
            } catch let error as PairingError where error == .codeExpired {
                await state.recordFailedPairing(error)
                throw error
            }

        case (.pairingAwaitingReveal(let pairing), .pairReveal(let reveal)):
            // Checked by the state, against the code on screen now, so parallel connections share one attempt limit.
            let checked = try await state.reveal(reveal, for: pairing, connectionID: id)
            guard advance(to: .pairingAwaitingConfirmations(checked, console: nil, grant: nil, role: nil)) else {
                await state.pairingEnded(connectionID: id, declined: false)
                return
            }

        case (.pairingAwaitingConfirmations(let pairing, nil, _, let role), .pairConfirm(let confirm)):
            let (console, grant) = try pairing.consoleConfirmation(from: confirm)
            phase = .pairingAwaitingConfirmations(pairing, console: console, grant: grant, role: role)
            await state.pairingConsoleConfirmed(connectionID: id, console: console, account: grant?.name)
            guard !isClosed else { return }
            try await finishPairingIfConfirmed()

        case (.awaitingFirstMessage, .hello(let hello)):
            var handshake = MacHandshake(identity: state.identity)
            let reply = try handshake.reply(to: hello)
            phase = .awaitingFinish(handshake)
            await write(.reply(reply))

        case (.awaitingFinish(let handshake), .finish(let finish)):
            let consoles = await state.consoles
            let membership = await state.membership
            let (channel, console, chain) = try handshake.accept(finish, trustChain: { identity, chain -> Bool in
                // A console paired on its own, or a device whose chain leads to the workspace this Mac pinned.
                if let chain { return membership?.role(for: identity, chain: chain) != nil }
                return consoles.contains { $0.identity.isSameDevice(as: identity) }
            })
            guard advance(to: .open(channel, console: console, chain: chain)) else { return }
            await state.consoleConnected(connectionID: id, console: console, chain: chain)

        case (.open(var channel, let console, let chain), .sealed(let frame)):
            let request = try JSONDecoder().decode(Envelope.self, from: try channel.open(frame))
            // Looked up again for every request, so a revocation or a changed role takes effect at once.
            guard let paired = await state.authorize(console, chain: chain) else {
                throw AgentRefusal(chain == nil ? "This console's pairing was revoked." : "This device was removed from the account.")
            }
            guard !isClosed else { return }
            let response: Envelope
            if Operation.workspace.contains(request.operation), request.kind == .request,
               request.version == RemoteProtocolVersion.current {
                response = await state.handleWorkspace(request, from: paired, viaWorkspace: chain != nil)
            } else {
                let (answer, record) = await handler.handle(request, from: paired, settings: await state.settings)
                if let record { await state.recordAction(by: paired, event: record.event, outcome: record.outcome) }
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

    /// The person at this Mac decided; `role` nil means the words did not match.
    func localDecision(_ role: ConsoleRole?) async {
        guard case .pairingAwaitingConfirmations(let pairing, let console, let grant, nil) = phase else { return }
        guard let role else {
            await state.pairingEnded(connectionID: id, declined: true)
            phase = .awaitingFirstMessage
            await close(reason: "The words were not confirmed on this Mac.")
            return
        }
        phase = .pairingAwaitingConfirmations(pairing, console: console, grant: grant, role: role)
        do {
            try await finishPairingIfConfirmed()
        } catch {
            await close(reason: Self.reason(for: error))
        }
    }

    private func finishPairingIfConfirmed() async throws {
        guard case .pairingAwaitingConfirmations(let pairing, let console?, let grant, let role?) = phase else { return }
        // The console's Confirm and the decision here can both arrive while the other is still awaiting: whichever gets
        // here first finishes the pairing, and the other finds nothing left to do.
        phase = .finishingPairing
        // Only send the Confirm (which makes the console pin this Mac) once this Mac has stored the console.
        let outcome = await state.completePairing(connectionID: id, console: console, role: role, grant: grant)
        guard outcome.completed else { throw AgentRefusal("Pairing was cancelled on this Mac.") }
        let confirm = try pairing.confirm(claim: outcome.claim)
        // The console may go straight on to a handshake on this connection.
        guard advance(to: .awaitingFirstMessage) else { return }
        await write(.pairConfirm(confirm))
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
