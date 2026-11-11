import Foundation
import RemoteCrypto

// "Allow from anywhere": the Mac keeps one outbound WebSocket to the MacPeek Remote relay, so consoles of its account
// reach it from any network without an open port. Each console that connects becomes a stream on that socket and gets
// its own `AgentConnection`, exactly as a TCP connection on the local network does: pairing is refused by the relay
// (only consoles of the account get through), and the SIGMA-I handshake, the encryption and the checks on every request
// are the same. The relay sees which Mac, addresses, times and byte counts, never what is inside.
//
// The protocol on the socket is in macpeek-remote's cloud/src/relay.ts: text messages are control (JSON), binary
// messages are data prefixed with the stream's number (4 bytes, big-endian).

/// One message on a WebSocket.
public enum RelaySocketMessage: Equatable, Sendable {
    case text(String)
    case data(Data)
}

/// A WebSocket to the relay. `receive` returns nil once the socket has closed.
public protocol RelaySocket: AnyObject, Sendable {
    func send(_ message: RelaySocketMessage) async throws
    func receive() async throws -> RelaySocketMessage?
    func close()
}

/// Opens a socket to `url`.
public typealias RelaySocketFactory = @Sendable (URL) async throws -> RelaySocket

/// Why a relay connection ended, and so what the client does next.
public enum RelayEnd: Error, Equatable, Sendable {
    /// The Mac is not in a MacPeek Remote account (any more): nothing gets through until it is.
    case notInAccount
    /// The relay did not accept the Mac's signature: a protocol mismatch, not worth retrying soon.
    case refused(String)
    /// The connection dropped, or the relay closed it (another connection from this Mac, a restart).
    case disconnected
    /// The relay sent something this Mac does not understand.
    case protocolError
}

enum RelayControl {
    static func decode(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return object as? [String: Any]
    }

    static func encode(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// The stream number of a control message: a JSON number from 1 to 2³²−1.
    static func stream(_ object: [String: Any]) -> UInt32? {
        // JSONSerialization gives NSNumber on Apple platforms and Int or Double on Linux.
        let value: Int64
        if let int = object["stream"] as? Int {
            value = Int64(int)
        } else if let double = object["stream"] as? Double, double.rounded() == double, abs(double) < 1e15 {
            value = Int64(double)
        } else {
            return nil
        }
        guard value > 0, value <= Int64(UInt32.max) else { return nil }
        return UInt32(value)
    }

    static func header(_ stream: UInt32) -> Data {
        Data([UInt8(stream >> 24), UInt8((stream >> 16) & 0xff), UInt8((stream >> 8) & 0xff), UInt8(stream & 0xff)])
    }

    static func split(_ data: Data) -> (stream: UInt32, payload: Data)? {
        guard data.count >= 4 else { return nil }
        let bytes = [UInt8](data.prefix(4))
        let stream = UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
        return (stream, Data(data.dropFirst(4)))
    }
}

/// One authenticated connection to the relay: answers the challenge, then serves every console stream until the socket
/// ends. `run` returns (or throws) when it does; `RelayClient` decides whether and when to connect again.
public actor RelaySession {
    /// The relay's pieces are at most this big; larger sends are split (the stream is bytes, framing is inside).
    public static let chunkSize = 64 * 1024

    private let socket: RelaySocket
    private let state: AgentState
    private let handler: RequestHandler
    private let identity: DeviceIdentity
    private var streams: [UInt32: (connection: AgentConnection, input: AsyncStream<Data>.Continuation)] = [:]
    private let onReady: (@Sendable () -> Void)?

    public init(socket: RelaySocket, state: AgentState, handler: RequestHandler, identity: DeviceIdentity,
                onReady: (@Sendable () -> Void)? = nil) {
        self.socket = socket
        self.state = state
        self.handler = handler
        self.identity = identity
        self.onReady = onReady
    }

    /// The number of consoles connected through this session now.
    public var streamCount: Int { streams.count }

    public func run() async throws {
        defer { socket.close() }
        do {
            try await authenticate()
            onReady?()
            while let message = try await socket.receive() {
                try await handle(message)
            }
            await endAll()
            throw RelayEnd.disconnected
        } catch {
            await endAll()
            throw error
        }
    }

    private func authenticate() async throws {
        guard case .text(let text)? = try await socket.receive(), let challenge = RelayControl.decode(text),
              challenge["type"] as? String == "challenge", let nonce = challenge["nonce"] as? String else {
            throw RelayEnd.protocolError
        }
        let answer = try RelayAuth.answer(nonce: nonce, by: identity)
        try await socket.send(.text(RelayControl.encode([
            "type": "auth", "macKey": answer.macKey.base64EncodedString(), "signature": answer.signature.base64EncodedString(),
        ])))
        while true {
            guard let message = try await socket.receive() else { throw RelayEnd.disconnected }
            guard case .text(let text) = message, let reply = RelayControl.decode(text) else { throw RelayEnd.protocolError }
            switch reply["type"] as? String {
            case "ready": return
            case "error":
                let error = reply["error"] as? String ?? "refused"
                throw error == "not_in_account" ? RelayEnd.notInAccount : RelayEnd.refused(error)
            case "pong": continue
            default: throw RelayEnd.protocolError
            }
        }
    }

    private func handle(_ message: RelaySocketMessage) async throws {
        switch message {
        case .text(let text):
            if text == "pong" { return }
            guard let control = RelayControl.decode(text) else { return }
            switch control["type"] as? String {
            case "open":
                guard let stream = RelayControl.stream(control) else { return }
                await open(stream)
            case "close":
                guard let stream = RelayControl.stream(control) else { return }
                // The console went away: its connection ends as a dropped TCP connection does.
                streams.removeValue(forKey: stream)?.input.finish()
            default:
                // Newer relays may say more; this Mac ignores what it does not know.
                return
            }
        case .data(let data):
            guard let piece = RelayControl.split(data) else { throw RelayEnd.protocolError }
            if let entry = streams[piece.stream] {
                entry.input.yield(piece.payload)
            } else {
                try? await socket.send(.text(RelayControl.encode(["type": "close", "stream": Int(piece.stream)])))
            }
        }
    }

    private func open(_ stream: UInt32) async {
        if let old = streams.removeValue(forKey: stream) { old.input.finish() }
        let socket = self.socket
        let header = RelayControl.header(stream)
        let connection = AgentConnection(
            state: state, handler: handler,
            send: { bytes in
                var offset = 0
                while offset < bytes.count {
                    let end = min(offset + RelaySession.chunkSize, bytes.count)
                    var piece = header
                    piece.append(bytes.subdata(in: (bytes.startIndex + offset)..<(bytes.startIndex + end)))
                    do { try await socket.send(.data(piece)) } catch { return }
                    offset = end
                }
            },
            onClose: { [weak self] in await self?.closed(stream) })
        // Bytes are handed to the connection in order, one piece at a time, without holding up other streams.
        let (input, continuation) = AsyncStream<Data>.makeStream()
        streams[stream] = (connection, continuation)
        Task {
            await connection.start()
            for await bytes in input { await connection.receive(bytes) }
            await connection.disconnected()
        }
    }

    /// The agent ended a console's connection (refused it, revoked it, switched off): tell the relay to close it.
    private func closed(_ stream: UInt32) async {
        guard let entry = streams.removeValue(forKey: stream) else { return }
        entry.input.finish()
        try? await socket.send(.text(RelayControl.encode(["type": "close", "stream": Int(stream)])))
    }

    private func endAll() async {
        let ended = streams.values
        streams.removeAll()
        for entry in ended { entry.input.finish() }
    }

    /// Keeps NAT and proxies from dropping a quiet connection; the relay answers without waking up.
    func ping() async throws {
        try await socket.send(.text("ping"))
    }
}

/// Keeps this Mac connected to the relay while "Allow from anywhere" is on, reconnecting after drops with a growing
/// delay. Only Macs in a MacPeek Remote account can connect: the relay checks the Mac's claim.
public actor RelayClient {
    public enum Status: Equatable, Sendable {
        case off
        case connecting
        case connected
        /// The relay says this Mac is not in an account; it tries again later in case it joins one.
        case notInAccount
        /// The last attempt failed; the next one is at `retryAt`.
        case waiting(retryAt: Date, reason: String)
    }

    /// The relay next to the service (`AccountService`): production, or staging when MacPeek points at staging.
    /// `MACPEEK_RELAY_URL` in the environment points a development build at any relay.
    public static var defaultBaseURL: URL {
        if let override = ProcessInfo.processInfo.environment["MACPEEK_RELAY_URL"], let url = URL(string: override) { return url }
        return AccountService.relayURL(for: AccountService.baseURL())
    }

    /// The Mac's socket URL: `<base>/relay/mac/<mac id>`.
    public static func url(base: URL, identity: DeviceIdentity) -> URL {
        base.appendingPathComponent("relay").appendingPathComponent("mac")
            .appendingPathComponent(RelayAuth.macID(of: identity.publicIdentity.signingKey))
    }

    /// Delay before the attempt after `failures` failed ones in a row: 2 s doubling to 5 minutes, with jitter.
    public static func backoff(after failures: Int, random: Double = Double.random(in: 0.8...1.2)) -> TimeInterval {
        let base = min(300, 2 * pow(2, Double(max(0, failures - 1))))
        return base * random
    }

    /// How often the Mac pings the relay while connected.
    public static let pingInterval: TimeInterval = 30
    /// How long a Mac that is not in an account waits before asking again.
    public static let notInAccountRetry: TimeInterval = 15 * 60

    private let state: AgentState
    private let handler: RequestHandler
    private let identity: DeviceIdentity
    private let baseURL: URL
    private let makeSocket: RelaySocketFactory
    private let onStatus: @Sendable (Status) -> Void
    private var task: Task<Void, Never>?
    private var generation = 0
    /// Whether the current attempt got as far as the relay's "ready".
    private var wasReady = false
    private var socket: RelaySocket?

    public init(state: AgentState, handler: RequestHandler, identity: DeviceIdentity, baseURL: URL = RelayClient.defaultBaseURL,
                makeSocket: @escaping RelaySocketFactory, onStatus: @escaping @Sendable (Status) -> Void) {
        self.state = state
        self.handler = handler
        self.identity = identity
        self.baseURL = baseURL
        self.makeSocket = makeSocket
        self.onStatus = onStatus
    }

    public var isRunning: Bool { task != nil }

    public func start() {
        guard task == nil else { return }
        generation += 1
        let generation = generation
        task = Task { [weak self] in await self?.loop(generation) }
    }

    /// Ends the connection and every console stream on it.
    public func stop() {
        task?.cancel()
        task = nil
        generation += 1
        // Closing the socket ends a session waiting for the next message at once.
        socket?.close()
        socket = nil
        onStatus(.off)
    }

    /// Connects again at once, for example after the network came back or the Mac joined an account.
    public func reconnectNow() {
        guard task != nil else { return }
        stop()
        start()
    }

    private func loop(_ generation: Int) async {
        var failures = 0
        let url = Self.url(base: baseURL, identity: identity)
        while !Task.isCancelled, generation == self.generation {
            report(.connecting, generation)
            wasReady = false
            var wait: TimeInterval
            var status: Status
            do {
                let socket = try await makeSocket(url)
                guard generation == self.generation else {
                    socket.close()
                    return
                }
                self.socket = socket
                let session = RelaySession(socket: socket, state: state, handler: handler, identity: identity,
                                           onReady: { [weak self] in
                                               guard let client = self else { return }
                                               Task { await client.ready(generation) }
                                           })
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask { try await session.run() }
                    group.addTask {
                        while !Task.isCancelled {
                            try await Task.sleep(nanoseconds: UInt64(Self.pingInterval * 1_000_000_000))
                            try await session.ping()
                        }
                    }
                    // Whichever ends first (the session, or a ping that could not be sent) ends both.
                    _ = try await group.next()
                    group.cancelAll()
                    socket.close()
                }
                failures = 0
                wait = Self.backoff(after: 1)
                status = .waiting(retryAt: Date().addingTimeInterval(wait), reason: "The connection to the relay ended.")
            } catch RelayEnd.notInAccount {
                failures = 0
                wait = Self.notInAccountRetry
                status = .notInAccount
            } catch {
                if Task.isCancelled { return }
                if wasReady {
                    // A connection that worked and then dropped (sleep, a network change, a relay restart): soon.
                    failures = 1
                } else {
                    failures += 1
                }
                wait = Self.backoff(after: failures)
                status = .waiting(retryAt: Date().addingTimeInterval(wait), reason: Self.describe(error))
            }
            if Task.isCancelled || generation != self.generation { return }
            report(status, generation)
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
    }

    private func ready(_ generation: Int) {
        guard generation == self.generation else { return }
        wasReady = true
        report(.connected, generation)
    }

    private func report(_ status: Status, _ generation: Int) {
        guard generation == self.generation else { return }
        onStatus(status)
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case RelayEnd.notInAccount: return "This Mac is not in a MacPeek Remote account."
        case RelayEnd.refused: return "The relay did not accept this Mac. Update MacPeek."
        case RelayEnd.disconnected: return "The connection to the relay ended."
        case RelayEnd.protocolError: return "The relay sent something unexpected. Update MacPeek."
        default: return "Could not reach the relay: \(error.localizedDescription)"
        }
    }
}
