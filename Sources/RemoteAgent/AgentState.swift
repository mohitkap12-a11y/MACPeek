import Foundation
import RemoteCrypto
import RemoteProtocol

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
        /// Set when that console is signed in to an account: confirming adds this Mac to the account, so every device
        /// in it can connect (with the access chosen here). The account's name, for people.
        public var account: String?
    }

    public struct Snapshot: Equatable, Sendable {
        public let settings: RemoteSettings
        public let identity: PublicIdentity
        public let consoles: [PairedConsole]
        public let connectedConsoles: Set<Data>
        public let pairingCode: PairingCode?
        public let pendingPairing: PendingPairing?
        public let log: ActivityLog
        /// The account this Mac belongs to, if any (protocol version 2).
        public let membership: WorkspaceMembership?
    }

    public static let localActor = "This Mac"

    public let identity: DeviceIdentity
    private let store: AgentStoring
    private let clock: @Sendable () -> Date
    private var onChange: (@Sendable () -> Void)?

    public private(set) var settings: RemoteSettings
    public private(set) var consoles: [PairedConsole]
    public private(set) var log: ActivityLog
    public private(set) var membership: WorkspaceMembership?
    public private(set) var pairingCode: PairingCode?
    private var failedAttempts = 0
    public private(set) var pendingPairing: PendingPairing?
    private var connections: [UUID: AgentConnection] = [:]
    /// The console each authenticated connection belongs to.
    private var connectionConsoles: [UUID: Data] = [:]
    /// The workspace chain of each connection that came in through the workspace.
    private var connectionChains: [UUID: WorkspaceChain] = [:]

    public init(identity: DeviceIdentity, store: AgentStoring, settings: RemoteSettings = RemoteSettings(),
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.identity = identity
        self.store = store
        self.clock = clock
        self.settings = settings
        consoles = (try? store.loadConsoles()) ?? []
        log = (try? store.loadLog()) ?? ActivityLog()
        membership = try? store.loadMembership()
    }

    public func setOnChange(_ handler: (@Sendable () -> Void)?) {
        onChange = handler
    }

    public func snapshot() -> Snapshot {
        Snapshot(settings: settings, identity: identity.publicIdentity, consoles: consoles,
                 connectedConsoles: Set(connectionConsoles.values), pairingCode: pairingCode, pendingPairing: pendingPairing,
                 log: log, membership: membership)
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

    /// Checks a console's Reveal against the code on screen now, in one step, so the attempt limit holds however many
    /// connections a console opens: a pairing begun before the code was withdrawn (after too many wrong guesses, a
    /// cancel or a new code) cannot keep guessing with it. On success the pairing waits for the person here.
    func reveal(_ reveal: PairingMessage.Reveal, for pairing: MacPairing, connectionID: UUID) throws -> MacPairing {
        guard settings.isEnabled, let code = pairingCode, code == pairing.code, pendingPairing == nil else {
            throw AgentRefusal("This Mac is not showing a pairing code.")
        }
        var pairing = pairing
        let words: [String]
        do {
            words = try pairing.words(after: reveal, now: clock())
        } catch let error as PairingError where error == .wrongCode || error == .codeExpired {
            recordFailedPairing(error)
            throw error
        }
        pendingPairing = PendingPairing(connectionID: connectionID, words: words, console: nil)
        changed()
        return pairing
    }

    func pairingConsoleConfirmed(connectionID: UUID, console: PublicIdentity, account: String? = nil) {
        guard pendingPairing?.connectionID == connectionID else { return }
        pendingPairing?.console = console
        pendingPairing?.account = account
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

    /// Called by the connection once both people confirmed, before it sends the Mac's Confirm. `completed` is false when
    /// the pairing was cancelled meanwhile: then nothing is stored and the Confirm must not be sent. With a workspace
    /// grant this Mac joins that workspace (leaving any other) instead of pinning the console, and `claim` says so.
    func completePairing(connectionID: UUID, console: PublicIdentity, role: ConsoleRole,
                         grant: WorkspaceGrant? = nil) async -> (completed: Bool, claim: MacClaim?) {
        guard settings.isEnabled, pendingPairing?.connectionID == connectionID else { return (false, nil) }
        pendingPairing = nil
        pairingCode = nil
        consoles.removeAll { $0.identity.isSameDevice(as: console) }
        guard let grant else {
            consoles.append(PairedConsole(identity: console, role: role, pairedAt: clock()))
            try? store.saveConsoles(consoles)
            record(actor: Self.localActor, fingerprint: nil, event: "Paired \(console.name) (\(console.fingerprint))",
                   outcome: role.label)
            changed()
            return (true, nil)
        }
        try? store.saveConsoles(consoles)
        await join(grant, roleCap: role, movedFrom: nil,
                   event: "Paired \(console.name) (\(console.fingerprint)), adding this Mac to \(grant.name)'s account")
        return (true, try? MacClaim.sign(by: identity, workspaceID: grant.workspaceID, time: Self.milliseconds(clock())))
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

    /// Who this is and what it may do: a device of this Mac's workspace (its chain checked against the pinned key and
    /// the newest revocation list) or a console paired on its own. Checked on every handshake and every request.
    func authorize(_ identity: PublicIdentity, chain: WorkspaceChain?) -> PairedConsole? {
        if let chain {
            guard let membership, let role = membership.role(for: identity, chain: chain) else { return nil }
            return PairedConsole(identity: identity, role: role, pairedAt: membership.joinedAt,
                                 lastConnected: membership.devices.first { $0.id == identity.signingKey }?.lastConnected)
        }
        return pairedConsole(identity)
    }

    func consoleConnected(connectionID: UUID, console: PublicIdentity, chain: WorkspaceChain? = nil) {
        connectionConsoles[connectionID] = console.signingKey
        if let chain, var membership {
            connectionChains[connectionID] = chain
            let device = WorkspaceDevice(identity: console, memberID: chain.device.memberID, lastConnected: clock())
            membership.devices.removeAll { $0.id == device.id }
            membership.devices.append(device)
            if membership.devices.count > 50 { membership.devices.removeFirst(membership.devices.count - 50) }
            self.membership = membership
            try? store.saveMembership(membership)
        } else if let index = consoles.firstIndex(where: { $0.identity.isSameDevice(as: console) }) {
            consoles[index].lastConnected = clock()
            try? store.saveConsoles(consoles)
        }
        changed()
    }

    // MARK: Workspace (protocol version 2)

    /// The most a device of the workspace may do here.
    public func setWorkspaceRoleCap(_ role: ConsoleRole) {
        guard var membership, membership.roleCap != role else { return }
        membership.roleCap = role
        self.membership = membership
        try? store.saveMembership(membership)
        record(actor: Self.localActor, fingerprint: nil, event: "Changed \(membership.name)'s account to \(role.label)",
               outcome: "Done")
        changed()
    }

    /// Removes this Mac from its account: no device of it can connect any more. Consoles paired on their own stay.
    public func leaveWorkspace() async {
        guard let old = membership else { return }
        membership = nil
        try? store.saveMembership(nil)
        record(actor: Self.localActor, fingerprint: nil, event: "Removed this Mac from \(old.name)'s account", outcome: "Done")
        await closeWorkspaceConnections(reason: "This Mac was removed from the account.")
        changed()
    }

    /// Undoes "Move this Mac to your account": the console that moved it is paired on its own again.
    public func undoMove() async {
        guard let old = membership, let console = old.movedFrom else { return }
        membership = nil
        try? store.saveMembership(nil)
        consoles.removeAll { $0.identity.isSameDevice(as: console.identity) }
        consoles.append(console)
        try? store.saveConsoles(consoles)
        record(actor: Self.localActor, fingerprint: nil,
               event: "Undid the move to \(old.name)'s account; \(console.identity.name) is paired on its own again", outcome: "Done")
        await closeWorkspaceConnections(reason: "This Mac was removed from the account.")
        changed()
    }

    /// Answers the `workspace.*` operations. `console` is who asked, already authorized.
    func handleWorkspace(_ request: Envelope, from console: PairedConsole, viaWorkspace: Bool) async -> Envelope {
        do {
            switch request.operation {
            case .workspaceStatus:
                return try request.response(status(viaWorkspace: viaWorkspace))
            case .workspaceAdopt:
                let grant = try request.body(WorkspaceGrant.self)
                guard !viaWorkspace else {
                    throw RemoteError(.notPermitted, "This console already reaches this Mac through its account.")
                }
                guard grant.isValid() else { throw RemoteError(.invalidPayload, "The account's certificate does not check out.") }
                if let membership, membership.workspaceID != grant.workspaceID {
                    throw RemoteError(.notPermitted,
                                      "This Mac belongs to another account. Pair it again at the Mac to move it to yours.")
                }
                consoles.removeAll { $0.identity.isSameDevice(as: console.identity) }
                try? store.saveConsoles(consoles)
                if membership == nil {
                    await join(grant, roleCap: console.role, movedFrom: console,
                               event: "\(console.identity.name) moved this Mac to \(grant.name)'s account")
                } else {
                    changed()
                }
                return try request.response(status(viaWorkspace: false))
            case .workspaceRevocations:
                let list = try request.body(RevocationList.self)
                guard let membership, list.isValid(workspaceID: membership.workspaceID, workspaceKey: membership.workspaceKey) else {
                    throw RemoteError(.invalidPayload, "That revocation list is not signed by this Mac's account.")
                }
                if list.sequence > membership.revocationSequence { await apply(list) }
                return try request.response(status(viaWorkspace: viaWorkspace))
            default:
                throw RemoteError(.unknownOperation, "This Mac does not know \(request.operation.rawValue).")
            }
        } catch let error as RemoteError {
            return request.failure(error)
        } catch {
            return request.failure(RemoteError(.invalidPayload, error.localizedDescription))
        }
    }

    private func status(viaWorkspace: Bool) throws -> WorkspaceStatus {
        WorkspaceStatus(workspaceID: membership?.workspaceID, revocationSequence: membership?.revocationSequence ?? 0,
                        claim: try membership.map { try MacClaim.sign(by: identity, workspaceID: $0.workspaceID,
                                                                       time: Self.milliseconds(clock())) },
                        viaWorkspace: viaWorkspace)
    }

    private func join(_ grant: WorkspaceGrant, roleCap: ConsoleRole, movedFrom: PairedConsole?, event: String) async {
        let previous = membership
        if let previous, previous.workspaceID == grant.workspaceID, previous.workspaceKey == grant.workspaceKey {
            // Paired again into the same account: keep what it knows, take the access chosen now.
            var same = previous
            same.roleCap = roleCap
            membership = same
        } else {
            membership = WorkspaceMembership(workspaceID: grant.workspaceID, workspaceKey: grant.workspaceKey, name: grant.name,
                                             roleCap: roleCap, joinedAt: clock(), movedFrom: movedFrom)
        }
        try? store.saveMembership(membership)
        record(actor: movedFrom?.identity.name ?? Self.localActor, fingerprint: movedFrom?.identity.fingerprint, event: event,
               outcome: roleCap.label)
        if let previous, previous.workspaceID != grant.workspaceID || previous.workspaceKey != grant.workspaceKey {
            await closeWorkspaceConnections(reason: "This Mac now belongs to another account.")
        }
        changed()
    }

    private func apply(_ list: RevocationList) async {
        guard var membership else { return }
        let before = membership.revokedKeys
        membership.revocations = list
        self.membership = membership
        try? store.saveMembership(membership)
        let added = Set(list.revokedKeys).subtracting(before).count
        record(actor: Self.localActor, fingerprint: nil, event: "Received \(membership.name)'s revocation list \(list.sequence)",
               outcome: added == 1 ? "1 device or member removed" : "\(added) devices or members removed")
        for (id, chain) in connectionChains {
            guard let key = connectionConsoles[id] else { continue }
            let identity = PublicIdentity(signingKey: key, name: "")
            if membership.role(for: identity, chain: chain) == nil {
                await connections[id]?.close(reason: "This device was removed from the account.")
            }
        }
        changed()
    }

    private func closeWorkspaceConnections(reason: String) async {
        for id in connectionChains.keys { await connections[id]?.close(reason: reason) }
    }

    static func milliseconds(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded()) }

    // MARK: Connections

    func register(_ connection: AgentConnection) {
        connections[connection.id] = connection
    }

    func unregister(_ connectionID: UUID) {
        connections[connectionID] = nil
        let wasAuthenticated = connectionConsoles.removeValue(forKey: connectionID) != nil
        connectionChains[connectionID] = nil
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
