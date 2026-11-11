import Foundation
import RemoteCrypto
import RemoteProtocol

/// Everything the agent knows, in one place: what the person allows, the MacPeek Remote account this Mac belongs to,
/// the open connections and the activity log. The app observes it through `onChange` and reads `snapshot()`.
///
/// A Mac is added to an account from the Mac ("Add to my account", `AccountJoinFlow`): its person signs in on the web and
/// MacPeek Remote on their main Mac approves it. From then on only devices of that account connect: their certificate
/// chain must lead to the account key this Mac pinned, and none of their keys may be on the account's revocation list.
public actor AgentState {
    public struct Snapshot: Equatable, Sendable {
        public let settings: RemoteSettings
        public let identity: PublicIdentity
        /// The devices connected now, by key.
        public let connectedConsoles: Set<Data>
        public let log: ActivityLog
        /// The account this Mac belongs to, if any.
        public let membership: WorkspaceMembership?
    }

    public static let localActor = "This Mac"

    public let identity: DeviceIdentity
    private let store: AgentStoring
    private let clock: @Sendable () -> Date
    private var onChange: (@Sendable () -> Void)?

    public private(set) var settings: RemoteSettings
    public private(set) var log: ActivityLog
    public private(set) var membership: WorkspaceMembership?
    private var connections: [UUID: AgentConnection] = [:]
    /// The device each authenticated connection belongs to.
    private var connectionConsoles: [UUID: Data] = [:]
    /// The account chain of each authenticated connection.
    private var connectionChains: [UUID: WorkspaceChain] = [:]

    public init(identity: DeviceIdentity, store: AgentStoring, settings: RemoteSettings = RemoteSettings(),
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.identity = identity
        self.store = store
        self.clock = clock
        self.settings = settings
        log = (try? store.loadLog()) ?? ActivityLog()
        membership = try? store.loadMembership()
    }

    public func setOnChange(_ handler: (@Sendable () -> Void)?) {
        onChange = handler
    }

    public func snapshot() -> Snapshot {
        Snapshot(settings: settings, identity: identity.publicIdentity, connectedConsoles: Set(connectionConsoles.values),
                 log: log, membership: membership)
    }

    // MARK: Settings

    /// Turning Remote management off ends every connection.
    public func update(_ newSettings: RemoteSettings) async {
        guard newSettings != settings else { return }
        let wasEnabled = settings.isEnabled
        let wasAnywhere = settings.allowFromAnywhere
        settings = newSettings
        if !newSettings.isEnabled {
            await closeAll(reason: "Remote management was turned off on this Mac.")
        }
        if wasEnabled != newSettings.isEnabled {
            record(actor: Self.localActor, fingerprint: nil,
                   event: newSettings.isEnabled ? "Turned Remote management on" : "Turned Remote management off", outcome: "Done")
        }
        if wasAnywhere != newSettings.allowFromAnywhere {
            record(actor: Self.localActor, fingerprint: nil,
                   event: newSettings.allowFromAnywhere ? "Turned Allow from anywhere on" : "Turned Allow from anywhere off",
                   outcome: "Done")
        }
        changed()
    }

    // MARK: Joining an account

    /// "Add to my account": the claim to send to the service before joining, so the Mac joins only once the service
    /// knows it. Checks the same things `joinAccount` does.
    public func claimForJoining(_ grant: WorkspaceGrant) throws -> MacClaim {
        guard settings.isEnabled else { throw AgentRefusal("Remote management is turned off on this Mac.") }
        guard grant.isValid() else { throw AgentRefusal("The account's certificate does not check out.") }
        return try MacClaim.sign(by: identity, workspaceID: grant.workspaceID, time: Self.milliseconds(clock()))
    }

    /// "Add to my account": its person signed in on the web, a console of the account approved and the service accepted
    /// the claim, so this Mac joins that account. `roleCap` is the most its devices may do here.
    public func joinAccount(_ grant: WorkspaceGrant, roleCap: ConsoleRole = .viewAndAct) async throws {
        guard settings.isEnabled else { throw AgentRefusal("Remote management is turned off on this Mac.") }
        guard grant.isValid() else { throw AgentRefusal("The account's certificate does not check out.") }
        let previous = membership
        if let previous, previous.workspaceID == grant.workspaceID, previous.workspaceKey == grant.workspaceKey {
            // Added again to the same account: keep what it knows.
            var same = previous
            same.roleCap = roleCap
            membership = same
        } else {
            membership = WorkspaceMembership(workspaceID: grant.workspaceID, workspaceKey: grant.workspaceKey, name: grant.name,
                                             roleCap: roleCap, joinedAt: clock())
        }
        try? store.saveMembership(membership)
        record(actor: Self.localActor, fingerprint: nil, event: "Added this Mac to \(grant.name)'s account", outcome: roleCap.label)
        if let previous, previous.workspaceID != grant.workspaceID || previous.workspaceKey != grant.workspaceKey {
            await closeAll(reason: "This Mac now belongs to another account.")
        }
        changed()
    }

    /// The most a device of the account may do here.
    public func setWorkspaceRoleCap(_ role: ConsoleRole) {
        guard var membership, membership.roleCap != role else { return }
        membership.roleCap = role
        self.membership = membership
        try? store.saveMembership(membership)
        record(actor: Self.localActor, fingerprint: nil, event: "Changed \(membership.name)'s account to \(role.label)",
               outcome: "Done")
        changed()
    }

    /// Removes this Mac from its account: no device can connect any more until it is added again.
    public func leaveWorkspace() async {
        guard let old = membership else { return }
        membership = nil
        try? store.saveMembership(nil)
        record(actor: Self.localActor, fingerprint: nil, event: "Removed this Mac from \(old.name)'s account", outcome: "Done")
        await closeAll(reason: "This Mac was removed from the account.")
        changed()
    }

    // MARK: Devices

    /// Who this is and what it may do: a device of this Mac's account, its chain checked against the pinned key and the
    /// newest revocation list. Checked on every handshake and every request.
    func authorize(_ identity: PublicIdentity, chain: WorkspaceChain) -> PairedConsole? {
        guard let membership, let role = membership.role(for: identity, chain: chain) else { return nil }
        return PairedConsole(identity: identity, role: role, pairedAt: membership.joinedAt,
                             lastConnected: membership.devices.first { $0.id == identity.signingKey }?.lastConnected)
    }

    func consoleConnected(connectionID: UUID, console: PublicIdentity, chain: WorkspaceChain) {
        connectionConsoles[connectionID] = console.signingKey
        connectionChains[connectionID] = chain
        if var membership {
            let device = WorkspaceDevice(identity: console, memberID: chain.device.memberID, lastConnected: clock())
            membership.devices.removeAll { $0.id == device.id }
            membership.devices.append(device)
            if membership.devices.count > 50 { membership.devices.removeFirst(membership.devices.count - 50) }
            self.membership = membership
            try? store.saveMembership(membership)
        }
        changed()
    }

    /// Answers the `workspace.*` operations. `console` is who asked, already authorized.
    func handleWorkspace(_ request: Envelope, from console: PairedConsole) async -> Envelope {
        do {
            switch request.operation {
            case .workspaceStatus:
                return try request.response(status())
            case .workspaceRevocations:
                let list = try request.body(RevocationList.self)
                guard let membership, list.isValid(workspaceID: membership.workspaceID, workspaceKey: membership.workspaceKey) else {
                    throw RemoteError(.invalidPayload, "That revocation list is not signed by this Mac's account.")
                }
                if list.sequence > membership.revocationSequence { await apply(list) }
                return try request.response(status())
            default:
                throw RemoteError(.unknownOperation, "This Mac does not know \(request.operation.rawValue).")
            }
        } catch let error as RemoteError {
            return request.failure(error)
        } catch {
            return request.failure(RemoteError(.invalidPayload, error.localizedDescription))
        }
    }

    private func status() throws -> WorkspaceStatus {
        WorkspaceStatus(workspaceID: membership?.workspaceID, revocationSequence: membership?.revocationSequence ?? 0,
                        claim: try membership.map { try MacClaim.sign(by: identity, workspaceID: $0.workspaceID,
                                                                       time: Self.milliseconds(clock())) },
                        viaWorkspace: true)
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

    static func milliseconds(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded()) }

    // MARK: Connections

    func register(_ connection: AgentConnection) {
        connections[connection.id] = connection
    }

    func unregister(_ connectionID: UUID) {
        connections[connectionID] = nil
        connectionChains[connectionID] = nil
        if connectionConsoles.removeValue(forKey: connectionID) != nil { changed() }
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
