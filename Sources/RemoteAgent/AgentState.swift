import Foundation
import RemoteCrypto

/// Everything the agent knows, in one place: what the person allows, who is paired, the pairing code on screen, the
/// pairing waiting for their confirmation, the open connections and the activity log. The app observes it through
/// `onChange` and reads `snapshot()`.
public actor AgentState {
    /// A pairing in progress, shown on this Mac once the console has proved it knows the code.
    public struct PendingPairing: Equatable, Sendable {
        public let connectionID: UUID
        public let words: [String]
        /// Known once the console's person has confirmed the words on their side.
        public var console: PublicIdentity?
    }

    public struct Snapshot: Equatable, Sendable {
        public let settings: RemoteSettings
        public let identity: PublicIdentity
        public let consoles: [PairedConsole]
        public let connectedConsoles: Set<Data>
        public let pairingCode: PairingCode?
        public let pendingPairing: PendingPairing?
        public let log: ActivityLog
    }

    public static let localActor = "This Mac"

    public let identity: DeviceIdentity
    private let store: AgentStoring
    private let clock: @Sendable () -> Date
    private var onChange: (@Sendable () -> Void)?

    public private(set) var settings: RemoteSettings
    public private(set) var consoles: [PairedConsole]
    public private(set) var log: ActivityLog
    public private(set) var pairingCode: PairingCode?
    private var failedAttempts = 0
    public private(set) var pendingPairing: PendingPairing?
    private var connections: [UUID: AgentConnection] = [:]
    /// The console each authenticated connection belongs to.
    private var connectionConsoles: [UUID: Data] = [:]

    public init(identity: DeviceIdentity, store: AgentStoring, settings: RemoteSettings = RemoteSettings(),
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.identity = identity
        self.store = store
        self.clock = clock
        self.settings = settings
        consoles = (try? store.loadConsoles()) ?? []
        log = (try? store.loadLog()) ?? ActivityLog()
    }

    public func setOnChange(_ handler: (@Sendable () -> Void)?) {
        onChange = handler
    }

    public func snapshot() -> Snapshot {
        Snapshot(settings: settings, identity: identity.publicIdentity, consoles: consoles,
                 connectedConsoles: Set(connectionConsoles.values), pairingCode: pairingCode, pendingPairing: pendingPairing,
                 log: log)
    }

    // MARK: Settings

    /// Turning Remote management off ends every connection and forgets any pairing in progress.
    public func update(_ newSettings: RemoteSettings) async {
        guard newSettings != settings else { return }
        let wasEnabled = settings.isEnabled
        settings = newSettings
        if !newSettings.isEnabled {
            pairingCode = nil
            pendingPairing = nil
            await closeAll(reason: "Remote management was turned off on this Mac.")
        }
        if wasEnabled != newSettings.isEnabled {
            record(actor: Self.localActor, fingerprint: nil,
                   event: newSettings.isEnabled ? "Turned Remote management on" : "Turned Remote management off", outcome: "Done")
        }
        changed()
    }

    // MARK: Pairing

    /// Shows a new one-time code; the previous one, and any pairing using it, stops working.
    @discardableResult
    public func newPairingCode() async -> PairingCode? {
        guard settings.isEnabled else { return nil }
        await cancelPendingPairing()
        let code = PairingCode.generate(now: clock())
        pairingCode = code
        failedAttempts = 0
        changed()
        return code
    }

    public func cancelPairing() async {
        pairingCode = nil
        await cancelPendingPairing()
        changed()
    }

    /// A connection asks to pair. Returns nil when there is no code on screen, it has expired, or another pairing is
    /// already in progress.
    func beginPairing() -> MacPairing? {
        guard settings.isEnabled, let code = pairingCode, pendingPairing == nil else { return nil }
        guard !code.isExpired(at: clock()) else {
            pairingCode = nil
            changed()
            return nil
        }
        return MacPairing(identity: identity, code: code)
    }

    /// A console sent the wrong code. After `PairingCode.maximumAttempts` the code is withdrawn.
    func recordFailedPairing(_ error: PairingError) {
        failedAttempts += 1
        if failedAttempts >= PairingCode.maximumAttempts || error == .codeExpired { pairingCode = nil }
        record(actor: Self.localActor, fingerprint: nil, event: "Pairing attempt refused",
               outcome: error == .codeExpired ? "Code expired" : "Wrong code")
        changed()
    }

    func pairingNeedsConfirmation(connectionID: UUID, words: [String]) {
        pendingPairing = PendingPairing(connectionID: connectionID, words: words, console: nil)
        changed()
    }

    func pairingConsoleConfirmed(connectionID: UUID, console: PublicIdentity) {
        guard pendingPairing?.connectionID == connectionID else { return }
        pendingPairing?.console = console
        changed()
    }

    /// The person at this Mac checked the words. `role` nil means they did not match, or they declined.
    public func resolvePairing(role: ConsoleRole?) async {
        guard let pending = pendingPairing, let connection = connections[pending.connectionID] else {
            pendingPairing = nil
            changed()
            return
        }
        await connection.localDecision(role)
    }

    /// Called by the connection once both people confirmed and the Mac's Confirm has been sent.
    func completePairing(connectionID: UUID, console: PublicIdentity, role: ConsoleRole) {
        guard pendingPairing?.connectionID == connectionID else { return }
        pendingPairing = nil
        pairingCode = nil
        consoles.removeAll { $0.identity.isSameDevice(as: console) }
        consoles.append(PairedConsole(identity: console, role: role, pairedAt: clock()))
        try? store.saveConsoles(consoles)
        record(actor: Self.localActor, fingerprint: nil, event: "Paired \(console.name) (\(console.fingerprint))",
               outcome: role.label)
        changed()
    }

    func pairingEnded(connectionID: UUID, declined: Bool) {
        guard pendingPairing?.connectionID == connectionID else { return }
        pendingPairing = nil
        if declined { record(actor: Self.localActor, fingerprint: nil, event: "Pairing declined", outcome: "Words not confirmed") }
        changed()
    }

    private func cancelPendingPairing() async {
        guard let pending = pendingPairing else { return }
        pendingPairing = nil
        await connections[pending.connectionID]?.close(reason: "Pairing was cancelled on this Mac.")
    }

    // MARK: Consoles

    public func setRole(_ role: ConsoleRole, for consoleID: Data) {
        guard let index = consoles.firstIndex(where: { $0.id == consoleID }), consoles[index].role != role else { return }
        consoles[index].role = role
        try? store.saveConsoles(consoles)
        record(actor: Self.localActor, fingerprint: nil, event: "Changed \(consoles[index].identity.name) to \(role.label)",
               outcome: "Done")
        changed()
    }

    /// Forgets the console and ends its connections. It has to pair again to reconnect.
    public func revoke(_ consoleID: Data) async {
        guard let index = consoles.firstIndex(where: { $0.id == consoleID }) else { return }
        let console = consoles.remove(at: index)
        try? store.saveConsoles(consoles)
        record(actor: Self.localActor, fingerprint: nil, event: "Revoked \(console.identity.name) (\(console.identity.fingerprint))",
               outcome: "Done")
        for (id, key) in connectionConsoles where key == consoleID {
            await connections[id]?.close(reason: "This console's pairing was revoked.")
        }
        changed()
    }

    /// The paired console with this key, if any: checked on every handshake and every request.
    func pairedConsole(_ identity: PublicIdentity) -> PairedConsole? {
        consoles.first { $0.identity.isSameDevice(as: identity) }
    }

    func consoleConnected(connectionID: UUID, console: PublicIdentity) {
        connectionConsoles[connectionID] = console.signingKey
        if let index = consoles.firstIndex(where: { $0.identity.isSameDevice(as: console) }) {
            consoles[index].lastConnected = clock()
            try? store.saveConsoles(consoles)
        }
        changed()
    }

    // MARK: Connections

    func register(_ connection: AgentConnection) {
        connections[connection.id] = connection
    }

    func unregister(_ connectionID: UUID) {
        connections[connectionID] = nil
        let wasAuthenticated = connectionConsoles.removeValue(forKey: connectionID) != nil
        if pendingPairing?.connectionID == connectionID { pendingPairing = nil }
        if wasAuthenticated || pendingPairing == nil { changed() }
    }

    public func closeAll(reason: String) async {
        for connection in connections.values { await connection.close(reason: reason) }
    }

    // MARK: Activity log

    func record(actor: String, fingerprint: String?, event: String, outcome: String) {
        log.append(date: clock(), actor: actor, fingerprint: fingerprint, event: event, outcome: outcome)
        try? store.saveLog(log)
    }

    func recordAction(by console: PairedConsole, event: String, outcome: String) {
        record(actor: console.identity.name, fingerprint: console.identity.fingerprint, event: event, outcome: outcome)
        changed()
    }

    private func changed() {
        onChange?()
    }
}
