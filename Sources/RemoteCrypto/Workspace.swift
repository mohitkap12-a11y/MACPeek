import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

// Protocol version 2: a Mac can trust a MacPeek account (a workspace) instead of one console.
//
// The person at the Mac still pairs once, with the code and the four words. The console then hands over the
// workspace's public key; the Mac pins it with the access the person chose, and from then on accepts any device that
// shows a chain of certificates back to that key:
//
//   workspace key ─signs─▶ member certificate (─signs─▶ member certificate) ─signs─▶ device certificate
//
// The second member certificate exists only for team admins (they certify members with their own key, never holding
// the workspace key). A signed, numbered revocation list withdraws devices and members; the Mac only ever accepts a
// higher number. The Mac also signs a claim, "this Mac belongs to this workspace", which the MacPeek service uses to
// route relay connections and count Macs. Version 1 pairings (one pinned console key) keep working.
//
// Every signed message is UTF-8 text, its fields joined by "\n", keys in standard base64, times in milliseconds since
// 1970. The same strings are built by MacPeek Remote and checked by the MacPeek service (cloud/src/crypto.ts there).
// No field may contain a newline, so a message can only be read one way.

public enum WorkspaceError: Error, Equatable, Sendable {
    case invalidKey
    case invalidField
    case invalidSignature
    case wrongWorkspace
    case chainTooLong
    case issuerMayNotCertify
    case wrongDevice
    case revoked
}

/// What a member may do in a workspace. A Mac applies the lower of this and the access chosen at pairing on the Mac.
public enum WorkspaceRole: String, Codable, Sendable, CaseIterable {
    case owner, admin, member, viewer

    /// Whether this role may act at all (free ports, quit processes) where the Mac allows it.
    public var mayAct: Bool { self != .viewer }
    /// Whether a member certificate with this role may certify other members.
    public var mayCertifyMembers: Bool { self == .owner || self == .admin }
}

enum SignedText {
    static func join(_ fields: [String]) throws -> String {
        guard fields.allSatisfy({ !$0.contains("\n") && !$0.contains("\r") }) else { throw WorkspaceError.invalidField }
        return fields.joined(separator: "\n")
    }

    static func sign(_ message: String, privateKey: Data) throws -> Data {
        guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: privateKey) else { throw WorkspaceError.invalidKey }
        return try key.signature(for: Data(message.utf8))
    }

    static func isValid(_ signature: Data, of message: String, by publicKey: Data) -> Bool {
        guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey) else { return false }
        return key.isValidSignature(signature, for: Data(message.utf8))
    }

    static func publicKey(of privateKey: Data) throws -> Data {
        guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: privateKey) else { throw WorkspaceError.invalidKey }
        return key.publicKey.rawRepresentation
    }
}

/// Certifies a member's signing key, with their role, in one workspace.
public struct MemberCertificate: Equatable, Codable, Sendable {
    public let workspaceID: String
    public let memberID: String
    /// The member's Ed25519 public key (32 bytes).
    public let signingKey: Data
    public let role: WorkspaceRole
    public let issuedAt: Int64
    /// By the workspace key, or (for a second certificate in a chain) by an owner's or admin's member key.
    public let signature: Data

    public static func message(workspaceID: String, memberID: String, signingKey: Data, role: WorkspaceRole,
                               issuedAt: Int64) throws -> String {
        try SignedText.join(["macpeek-member-v1", workspaceID, memberID, signingKey.base64EncodedString(), role.rawValue,
                             String(issuedAt)])
    }

    public var signedMessage: String {
        get throws {
            try Self.message(workspaceID: workspaceID, memberID: memberID, signingKey: signingKey, role: role, issuedAt: issuedAt)
        }
    }

    /// Issues a certificate, signed with `issuerPrivateKey` (the workspace key, or an owner's or admin's member key).
    public static func issue(workspaceID: String, memberID: String, signingKey: Data, role: WorkspaceRole, issuedAt: Int64,
                             issuerPrivateKey: Data) throws -> MemberCertificate {
        let text = try message(workspaceID: workspaceID, memberID: memberID, signingKey: signingKey, role: role, issuedAt: issuedAt)
        return MemberCertificate(workspaceID: workspaceID, memberID: memberID, signingKey: signingKey, role: role,
                                 issuedAt: issuedAt, signature: try SignedText.sign(text, privateKey: issuerPrivateKey))
    }

    public init(workspaceID: String, memberID: String, signingKey: Data, role: WorkspaceRole, issuedAt: Int64, signature: Data) {
        self.workspaceID = workspaceID
        self.memberID = memberID
        self.signingKey = signingKey
        self.role = role
        self.issuedAt = issuedAt
        self.signature = signature
    }
}

/// Certifies a device's signing key (the key it uses in the session handshake) for one member.
public struct DeviceCertificate: Equatable, Codable, Sendable {
    public let workspaceID: String
    public let memberID: String
    public let deviceID: String
    public let signingKey: Data
    public let name: String
    public let issuedAt: Int64
    /// By the member's key.
    public let signature: Data

    public static func message(workspaceID: String, memberID: String, deviceID: String, signingKey: Data, name: String,
                               issuedAt: Int64) throws -> String {
        try SignedText.join(["macpeek-device-v1", workspaceID, memberID, deviceID, signingKey.base64EncodedString(), name,
                             String(issuedAt)])
    }

    public var signedMessage: String {
        get throws {
            try Self.message(workspaceID: workspaceID, memberID: memberID, deviceID: deviceID, signingKey: signingKey, name: name,
                             issuedAt: issuedAt)
        }
    }

    public static func issue(workspaceID: String, memberID: String, deviceID: String, signingKey: Data, name: String,
                             issuedAt: Int64, memberPrivateKey: Data) throws -> DeviceCertificate {
        // Names are for people; a newline would make the message ambiguous, so it becomes a space.
        let name = name.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        let text = try message(workspaceID: workspaceID, memberID: memberID, deviceID: deviceID, signingKey: signingKey,
                               name: name, issuedAt: issuedAt)
        return DeviceCertificate(workspaceID: workspaceID, memberID: memberID, deviceID: deviceID, signingKey: signingKey,
                                 name: name, issuedAt: issuedAt, signature: try SignedText.sign(text, privateKey: memberPrivateKey))
    }

    public init(workspaceID: String, memberID: String, deviceID: String, signingKey: Data, name: String, issuedAt: Int64,
                signature: Data) {
        self.workspaceID = workspaceID
        self.memberID = memberID
        self.deviceID = deviceID
        self.signingKey = signingKey
        self.name = name
        self.issuedAt = issuedAt
        self.signature = signature
    }
}

/// What a device shows a Mac to prove it belongs to a workspace.
public struct WorkspaceChain: Equatable, Codable, Sendable {
    /// One certificate (signed by the workspace key) or two (the second signed by an owner or admin in the first).
    public let members: [MemberCertificate]
    public let device: DeviceCertificate

    public init(members: [MemberCertificate], device: DeviceCertificate) {
        self.members = members
        self.device = device
    }

    /// Checks the chain against the workspace key a Mac pinned, for the device key that signed the handshake, and
    /// returns the member's role. Throws if any link is wrong or any key in it is revoked.
    public func verify(workspaceID: String, workspaceKey: Data, deviceKey: Data, revoked: Set<Data> = []) throws -> WorkspaceRole {
        guard !members.isEmpty else { throw WorkspaceError.invalidSignature }
        guard members.count <= 2 else { throw WorkspaceError.chainTooLong }
        var issuer = workspaceKey
        for (index, member) in members.enumerated() {
            guard member.workspaceID == workspaceID else { throw WorkspaceError.wrongWorkspace }
            if index > 0 {
                guard members[index - 1].role.mayCertifyMembers, member.role != .owner else {
                    throw WorkspaceError.issuerMayNotCertify
                }
            }
            guard SignedText.isValid(member.signature, of: try member.signedMessage, by: issuer) else {
                throw WorkspaceError.invalidSignature
            }
            guard !revoked.contains(member.signingKey) else { throw WorkspaceError.revoked }
            issuer = member.signingKey
        }
        let member = members[members.count - 1]
        guard device.workspaceID == workspaceID else { throw WorkspaceError.wrongWorkspace }
        guard device.memberID == member.memberID, device.signingKey == deviceKey else { throw WorkspaceError.wrongDevice }
        guard SignedText.isValid(device.signature, of: try device.signedMessage, by: issuer) else { throw WorkspaceError.invalidSignature }
        guard !revoked.contains(device.signingKey) else { throw WorkspaceError.revoked }
        return member.role
    }
}

/// The keys a workspace has withdrawn (devices and members), signed by the workspace key. Each list replaces the one
/// before and carries a higher sequence number, so an old list cannot be replayed to undo a revocation.
public struct RevocationList: Equatable, Codable, Sendable {
    public let workspaceID: String
    public let sequence: Int
    /// Sorted, so the signed message is the same however the list was built.
    public let revokedKeys: [Data]
    public let signature: Data

    public static func message(workspaceID: String, sequence: Int, revokedKeys: [Data]) throws -> String {
        let keys = revokedKeys.map { $0.base64EncodedString() }.sorted().joined(separator: ",")
        return try SignedText.join(["macpeek-revocations-v1", workspaceID, String(sequence), keys])
    }

    public static func issue(workspaceID: String, sequence: Int, revokedKeys: [Data], workspacePrivateKey: Data) throws -> RevocationList {
        let sorted = Array(Set(revokedKeys)).sorted { $0.base64EncodedString() < $1.base64EncodedString() }
        let text = try message(workspaceID: workspaceID, sequence: sequence, revokedKeys: sorted)
        return RevocationList(workspaceID: workspaceID, sequence: sequence, revokedKeys: sorted,
                              signature: try SignedText.sign(text, privateKey: workspacePrivateKey))
    }

    public init(workspaceID: String, sequence: Int, revokedKeys: [Data], signature: Data) {
        self.workspaceID = workspaceID
        self.sequence = sequence
        self.revokedKeys = revokedKeys
        self.signature = signature
    }

    public func isValid(workspaceID: String, workspaceKey: Data) -> Bool {
        guard self.workspaceID == workspaceID, sequence > 0, let text = try? Self.message(workspaceID: workspaceID, sequence: sequence,
                                                                                          revokedKeys: revokedKeys) else {
            return false
        }
        return SignedText.isValid(signature, of: text, by: workspaceKey)
    }
}

/// "This Mac belongs to this workspace", signed by the Mac's own key.
public struct MacClaim: Equatable, Codable, Sendable {
    /// The Mac's Ed25519 public key.
    public let macKey: Data
    public let workspaceID: String
    public let time: Int64
    public let signature: Data

    public static func message(macKey: Data, workspaceID: String, time: Int64) throws -> String {
        try SignedText.join(["macpeek-claim-v1", macKey.base64EncodedString(), workspaceID, String(time)])
    }

    public static func sign(by mac: DeviceIdentity, workspaceID: String, time: Int64) throws -> MacClaim {
        let key = mac.publicIdentity.signingKey
        let text = try message(macKey: key, workspaceID: workspaceID, time: time)
        return MacClaim(macKey: key, workspaceID: workspaceID, time: time, signature: try mac.signature(for: Data(text.utf8)))
    }

    public init(macKey: Data, workspaceID: String, time: Int64, signature: Data) {
        self.macKey = macKey
        self.workspaceID = workspaceID
        self.time = time
        self.signature = signature
    }

    public var isValid: Bool {
        guard let text = try? Self.message(macKey: macKey, workspaceID: workspaceID, time: time) else { return false }
        return SignedText.isValid(signature, of: text, by: macKey)
    }
}

/// What a console signed in to an account gives a Mac when pairing, or when moving a Mac paired before accounts into
/// the account: the workspace to pin, and the console's own chain in it.
public struct WorkspaceGrant: Equatable, Codable, Sendable {
    public let workspaceID: String
    /// The workspace's Ed25519 public key: what the Mac pins.
    public let workspaceKey: Data
    /// For people: whose account this is, e.g. the owner's email. Never used for trust.
    public let name: String
    public let chain: WorkspaceChain

    public init(workspaceID: String, workspaceKey: Data, name: String, chain: WorkspaceChain) {
        self.workspaceID = workspaceID
        self.workspaceKey = workspaceKey
        self.name = name
        self.chain = chain
    }

    /// The grant is consistent: the chain verifies against the workspace key it names.
    public func isValid() -> Bool {
        (try? chain.verify(workspaceID: workspaceID, workspaceKey: workspaceKey, deviceKey: chain.device.signingKey)) != nil
    }
}

/// Signing with a workspace key held as raw data (by owners, in their vault).
public enum WorkspaceKeys {
    public static func newPrivateKey() -> Data { Curve25519.Signing.PrivateKey().rawRepresentation }
    public static func publicKey(of privateKey: Data) throws -> Data { try SignedText.publicKey(of: privateKey) }
}
