import Foundation
import RemoteCrypto

/// What the person at this Mac allows. Everything is off until they turn it on: while `isEnabled` is false MacPeek does
/// not listen, does not advertise itself and connects nowhere.
public struct RemoteSettings: Equatable, Codable, Sendable {
    public var isEnabled: Bool
    /// Lets consoles paired to act free ports and quit processes. Reads are always allowed to paired consoles.
    public var allowActions: Bool

    public init(isEnabled: Bool = false, allowActions: Bool = false) {
        self.isEnabled = isEnabled
        self.allowActions = allowActions
    }
}

public enum ConsoleRole: String, Codable, Sendable, CaseIterable {
    case viewOnly
    case viewAndAct

    public var mayAct: Bool { self == .viewAndAct }

    public var label: String {
        switch self {
        case .viewOnly: return "View only"
        case .viewAndAct: return "View and act"
        }
    }
}

/// A console this Mac paired with. Only its public key is stored.
public struct PairedConsole: Identifiable, Equatable, Codable, Sendable {
    public var id: Data { identity.signingKey }
    public let identity: PublicIdentity
    public var role: ConsoleRole
    public let pairedAt: Date
    public var lastConnected: Date?

    public init(identity: PublicIdentity, role: ConsoleRole, pairedAt: Date, lastConnected: Date? = nil) {
        self.identity = identity
        self.role = role
        self.pairedAt = pairedAt
        self.lastConnected = lastConnected
    }
}

/// A device that reached this Mac through its workspace, kept for the person at the Mac to see.
public struct WorkspaceDevice: Identifiable, Equatable, Codable, Sendable {
    public var id: Data { identity.signingKey }
    public let identity: PublicIdentity
    public let memberID: String
    public var lastConnected: Date

    public init(identity: PublicIdentity, memberID: String, lastConnected: Date) {
        self.identity = identity
        self.memberID = memberID
        self.lastConnected = lastConnected
    }
}

/// The workspace (a MacPeek account) this Mac trusts: its pinned key, the access the person at the Mac chose, and the
/// newest revocation list. A Mac belongs to one workspace at a time.
public struct WorkspaceMembership: Equatable, Codable, Sendable {
    public let workspaceID: String
    public let workspaceKey: Data
    /// Whose account this is, for people (the owner's email). Never used for trust.
    public let name: String
    /// The most a device in the workspace may do here; each device gets the lower of this and its member's role.
    public var roleCap: ConsoleRole
    public let joinedAt: Date
    public var revocations: RevocationList?
    public var devices: [WorkspaceDevice]
    /// The console that moved this Mac in, when it was paired before: "Undo" pairs it again on its own.
    public let movedFrom: PairedConsole?

    public init(workspaceID: String, workspaceKey: Data, name: String, roleCap: ConsoleRole, joinedAt: Date,
                revocations: RevocationList? = nil, devices: [WorkspaceDevice] = [], movedFrom: PairedConsole? = nil) {
        self.workspaceID = workspaceID
        self.workspaceKey = workspaceKey
        self.name = name
        self.roleCap = roleCap
        self.joinedAt = joinedAt
        self.revocations = revocations
        self.devices = devices
        self.movedFrom = movedFrom
    }

    public var revokedKeys: Set<Data> { Set(revocations?.revokedKeys ?? []) }
    public var revocationSequence: Int { revocations?.sequence ?? 0 }

    /// The access a device with this chain gets here, or nil if the chain does not hold.
    public func role(for identity: PublicIdentity, chain: WorkspaceChain) -> ConsoleRole? {
        guard let memberRole = try? chain.verify(workspaceID: workspaceID, workspaceKey: workspaceKey,
                                                 deviceKey: identity.signingKey, revoked: revokedKeys) else { return nil }
        return memberRole.mayAct ? roleCap : .viewOnly
    }
}

/// Where the agent keeps who is paired and what happened. The identity's private key is not here: it is in the Keychain.
public protocol AgentStoring: Sendable {
    func loadConsoles() throws -> [PairedConsole]
    func saveConsoles(_ consoles: [PairedConsole]) throws
    func loadLog() throws -> ActivityLog
    func saveLog(_ log: ActivityLog) throws
    func loadMembership() throws -> WorkspaceMembership?
    /// Nil removes it.
    func saveMembership(_ membership: WorkspaceMembership?) throws
}

extension AgentStoring {
    // Stores written before protocol version 2 keep no workspace.
    public func loadMembership() throws -> WorkspaceMembership? { nil }
    public func saveMembership(_ membership: WorkspaceMembership?) throws {}
}

/// JSON files readable only by this user, in MacPeek's Application Support folder.
public struct FileAgentStore: AgentStoring {
    // A path rather than a URL: URL is not Sendable in every Foundation this builds against.
    private let directoryPath: String

    public init(directory: URL) {
        directoryPath = directory.path
    }

    public var directory: URL { URL(fileURLWithPath: directoryPath, isDirectory: true) }
    private var consolesURL: URL { directory.appendingPathComponent("paired-consoles.json") }
    private var logURL: URL { directory.appendingPathComponent("activity-log.json") }
    private var membershipURL: URL { directory.appendingPathComponent("workspace.json") }

    public func loadConsoles() throws -> [PairedConsole] { try load([PairedConsole].self, from: consolesURL) ?? [] }
    public func saveConsoles(_ consoles: [PairedConsole]) throws { try writePrivately(try JSONEncoder().encode(consoles), to: consolesURL) }
    public func loadLog() throws -> ActivityLog { try load(ActivityLog.self, from: logURL) ?? ActivityLog() }
    public func saveLog(_ log: ActivityLog) throws { try writePrivately(try JSONEncoder().encode(log), to: logURL) }
    public func loadMembership() throws -> WorkspaceMembership? { try load(WorkspaceMembership.self, from: membershipURL) }
    public func saveMembership(_ membership: WorkspaceMembership?) throws {
        guard let membership else {
            if FileManager.default.fileExists(atPath: membershipURL.path) { try FileManager.default.removeItem(at: membershipURL) }
            return
        }
        try writePrivately(try JSONEncoder().encode(membership), to: membershipURL)
    }

    private func load<Value: Decodable>(_ type: Value.Type, from url: URL) throws -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
    }
}

/// One entry in the activity log: an action a console asked for, or a change to who may connect.
public struct ActivityEntry: Identifiable, Equatable, Codable, Sendable {
    public var id: String { hash }
    public let date: Date
    /// The console's name, or "This Mac" for changes made here.
    public let actor: String
    /// The console's key fingerprint, or nil for changes made here.
    public let actorFingerprint: String?
    public let event: String
    public let outcome: String
    public let previousHash: String
    public let hash: String

    static func digest(date: Date, actor: String, fingerprint: String?, event: String, outcome: String, previous: String) -> String {
        let fields = [String(date.timeIntervalSince1970), actor, fingerprint ?? "", event, outcome, previous]
        return Digest.sha256Hex(Data(fields.joined(separator: "\u{1F}").utf8))
    }
}

/// An append-only log in which each entry includes the hash of the one before, so an edited or removed entry is
/// detectable. The oldest entries are dropped past `limit`; the chain is checked from the first entry kept.
public struct ActivityLog: Equatable, Codable, Sendable {
    public static let limit = 500
    public private(set) var entries: [ActivityEntry] = []

    public init(entries: [ActivityEntry] = []) {
        self.entries = entries
    }

    @discardableResult
    public mutating func append(date: Date = Date(), actor: String, fingerprint: String?, event: String, outcome: String) -> ActivityEntry {
        let previous = entries.last?.hash ?? ""
        let entry = ActivityEntry(date: date, actor: actor, actorFingerprint: fingerprint, event: event, outcome: outcome,
                                  previousHash: previous,
                                  hash: ActivityEntry.digest(date: date, actor: actor, fingerprint: fingerprint, event: event,
                                                             outcome: outcome, previous: previous))
        entries.append(entry)
        if entries.count > Self.limit { entries.removeFirst(entries.count - Self.limit) }
        return entry
    }

    /// True when every entry's hash matches its contents and links to the one before it.
    public var isIntact: Bool {
        for (index, entry) in entries.enumerated() {
            if index > 0, entry.previousHash != entries[index - 1].hash { return false }
            let expected = ActivityEntry.digest(date: entry.date, actor: entry.actor, fingerprint: entry.actorFingerprint,
                                                event: entry.event, outcome: entry.outcome, previous: entry.previousHash)
            if expected != entry.hash { return false }
        }
        return true
    }
}

/// Writes atomically and leaves the file readable and writable by this user only.
func writePrivately(_ data: Data, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
}
