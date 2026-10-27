import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// The public half of a device's long-term identity: what a paired Mac or console pins, and checks on every connection.
public struct PublicIdentity: Hashable, Codable, Sendable {
    /// Raw Ed25519 public key (32 bytes).
    public let signingKey: Data
    /// What the device calls itself, e.g. "Design Studio 01". Shown to people; never used for trust decisions.
    public let name: String

    public init(signingKey: Data, name: String) {
        self.signingKey = signingKey
        self.name = name
    }

    /// The first 8 bytes of SHA-256 of the key, as four groups: "7f3a 91c2 0be8 44d1". Shown so people can tell keys apart.
    public var fingerprint: String {
        let hex = SHA256.hash(data: signingKey).prefix(8).map { String(format: "%02x", $0) }.joined()
        return stride(from: 0, to: hex.count, by: 4).map { offset -> String in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            return String(hex[start..<hex.index(start, offsetBy: 4)])
        }.joined(separator: " ")
    }

    /// Same key, whatever the name says.
    public func isSameDevice(as other: PublicIdentity) -> Bool { signingKey == other.signingKey }

    public func isValidSignature(_ signature: Data, for data: Data) -> Bool {
        guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: signingKey) else { return false }
        return key.isValidSignature(signature, for: data)
    }
}

/// A device's long-term Ed25519 identity. The private key never leaves the device; the agent keeps it in the Keychain.
public struct DeviceIdentity: Sendable {
    /// Raw private key (32 bytes), kept as data so the identity can be stored and is `Sendable`.
    public let privateKeyData: Data
    public let name: String

    /// A new random identity.
    public init(name: String) {
        privateKeyData = Curve25519.Signing.PrivateKey().rawRepresentation
        self.name = name
    }

    /// An identity loaded from storage. Throws if the data is not a valid key.
    public init(name: String, privateKeyData: Data) throws {
        _ = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData)
        self.privateKeyData = privateKeyData
        self.name = name
    }

    public var publicIdentity: PublicIdentity {
        // The data was validated when the identity was made, so this cannot fail.
        let key = try! Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData)
        return PublicIdentity(signingKey: key.publicKey.rawRepresentation, name: name)
    }

    public func signature(for data: Data) throws -> Data {
        try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData).signature(for: data)
    }
}

public enum Digest {
    /// SHA-256 as lowercase hex.
    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
