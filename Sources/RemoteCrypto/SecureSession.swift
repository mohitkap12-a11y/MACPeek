import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

// Every connection after pairing, on the local network or through the relay, opens with this three-message handshake
// (the SIGMA-I pattern) and then encrypts every frame end to end:
//
//   console → Mac   Hello   a one-time key
//   Mac → console   Reply   a one-time key, plus the Mac's identity signed over both keys (encrypted)
//   console → Mac   Finish  the console's identity signed over the handshake (encrypted)
//
// Each side accepts only an identity it pinned when pairing; since protocol version 2 a console may instead show a
// certificate chain to the workspace key the Mac pinned (Workspace.swift), inside its encrypted Finish. One-time keys give forward secrecy: a stolen identity key
// cannot decrypt earlier sessions. Frames use ChaCha20-Poly1305 with a per-direction key and a counter nonce, so a
// frame that is changed, replayed, dropped or reordered is rejected.

public enum SessionError: Error, Equatable, Sendable {
    case unexpectedMessage
    case unsupportedVersion(Int)
    case invalidKey
    case untrustedPeer
    case invalidSignature
    case decryptionFailed
    case counterExhausted
}

public enum HandshakeMessage {
    public static let version = 1

    public struct Hello: Equatable, Codable, Sendable {
        public let version: Int
        public let ephemeralKey: Data
    }

    public struct Reply: Equatable, Codable, Sendable {
        public let ephemeralKey: Data
        public let sealedIdentity: Data
    }

    public struct Finish: Equatable, Codable, Sendable {
        public let sealedIdentity: Data
    }
}

/// An encrypted, ordered, two-way channel. `seal` before sending a frame; `open` each frame received, in order.
public struct SecureChannel: Sendable {
    private let sendKey: Data
    private let receiveKey: Data
    private var sendCounter: UInt64 = 0
    private var receiveCounter: UInt64 = 0

    init(sendKey: SymmetricKey, receiveKey: SymmetricKey) {
        self.sendKey = sendKey.withUnsafeBytes { Data($0) }
        self.receiveKey = receiveKey.withUnsafeBytes { Data($0) }
    }

    public mutating func seal(_ plaintext: Data) throws -> Data {
        guard sendCounter < .max else { throw SessionError.counterExhausted }
        let box = try ChaChaPoly.seal(plaintext, using: SymmetricKey(data: sendKey), nonce: try Self.nonce(sendCounter))
        sendCounter += 1
        // A fresh, zero-based Data: `ciphertext` is a slice and would keep its start index.
        return Data(box.ciphertext) + box.tag
    }

    public mutating func open(_ frame: Data) throws -> Data {
        guard receiveCounter < .max else { throw SessionError.counterExhausted }
        guard frame.count >= 16 else { throw SessionError.decryptionFailed }
        do {
            let box = try ChaChaPoly.SealedBox(nonce: try Self.nonce(receiveCounter), ciphertext: frame.dropLast(16),
                                               tag: frame.suffix(16))
            let plain = try ChaChaPoly.open(box, using: SymmetricKey(data: receiveKey))
            receiveCounter += 1
            return plain
        } catch {
            throw SessionError.decryptionFailed
        }
    }

    /// Four zero bytes, then the counter big-endian. Never reused: each direction has its own key.
    private static func nonce(_ counter: UInt64) throws -> ChaChaPoly.Nonce {
        try ChaChaPoly.Nonce(data: Data(count: 4) + withUnsafeBytes(of: counter.bigEndian) { Data($0) })
    }
}

/// Handshake keys and transcript, derived identically on both sides.
private struct HandshakeKeys {
    let transcript: Data
    let replyKey: SymmetricKey
    let finishKey: SymmetricKey
    let consoleToMac: SymmetricKey
    let macToConsole: SymmetricKey

    init(shared: SharedSecret, consoleKey: Data, macKey: Data) {
        let hash = Data(SHA256.hash(data: Data("macpeek-session-v1".utf8) + consoleKey + macKey))
        transcript = hash
        func key(_ info: String) -> SymmetricKey {
            shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: hash, sharedInfo: Data(info.utf8), outputByteCount: 32)
        }
        replyKey = key("reply")
        finishKey = key("finish")
        consoleToMac = key("console to mac traffic")
        macToConsole = key("mac to console traffic")
    }

    static func signedData(role: String, transcript: Data) -> Data { Data("macpeek-session-identity-v1 \(role)".utf8) + transcript }
}

private struct SignedIdentity: Codable {
    let identity: PublicIdentity
    let signature: Data
    /// The console's workspace chain, if it has one. Older Macs ignore it.
    var chain: WorkspaceChain?

    static func seal(_ identity: DeviceIdentity, role: String, transcript: Data, key: SymmetricKey,
                     chain: WorkspaceChain? = nil) throws -> Data {
        let signed = SignedIdentity(identity: identity.publicIdentity,
                                    signature: try identity.signature(for: HandshakeKeys.signedData(role: role, transcript: transcript)),
                                    chain: chain)
        return try ChaChaPoly.seal(try JSONEncoder().encode(signed), using: key).combined
    }

    static func open(_ sealed: Data, role: String, transcript: Data, key: SymmetricKey) throws -> PublicIdentity {
        try openSigned(sealed, role: role, transcript: transcript, key: key).identity
    }

    static func openSigned(_ sealed: Data, role: String, transcript: Data, key: SymmetricKey) throws -> SignedIdentity {
        guard let box = try? ChaChaPoly.SealedBox(combined: sealed), let plain = try? ChaChaPoly.open(box, using: key),
              let signed = try? JSONDecoder().decode(SignedIdentity.self, from: plain) else { throw SessionError.decryptionFailed }
        guard signed.identity.isValidSignature(signed.signature, for: HandshakeKeys.signedData(role: role, transcript: transcript)) else {
            throw SessionError.invalidSignature
        }
        return signed
    }
}

/// The console's side: it starts the connection.
public struct ConsoleHandshake {
    private let identity: DeviceIdentity
    private let chain: WorkspaceChain?
    private let ephemeral = Curve25519.KeyAgreement.PrivateKey()
    private var keys: HandshakeKeys?

    /// `chain` certifies `identity` in the workspace a Mac pinned; leave it nil for a Mac paired with this console alone.
    public init(identity: DeviceIdentity, chain: WorkspaceChain? = nil) {
        self.identity = identity
        self.chain = chain
    }

    public func hello() -> HandshakeMessage.Hello {
        HandshakeMessage.Hello(version: HandshakeMessage.version, ephemeralKey: ephemeral.publicKey.rawRepresentation)
    }

    /// Checks the Mac's identity with `trust` (is it the pinned key for that Mac?) and returns the Finish message, the
    /// channel and the Mac's identity.
    public mutating func finish(after reply: HandshakeMessage.Reply, trust: (PublicIdentity) -> Bool) throws
        -> (finish: HandshakeMessage.Finish, channel: SecureChannel, mac: PublicIdentity) {
        guard keys == nil else { throw SessionError.unexpectedMessage }
        guard let macKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: reply.ephemeralKey),
              let shared = try? ephemeral.sharedSecretFromKeyAgreement(with: macKey) else { throw SessionError.invalidKey }
        let keys = HandshakeKeys(shared: shared, consoleKey: ephemeral.publicKey.rawRepresentation, macKey: reply.ephemeralKey)
        let mac = try SignedIdentity.open(reply.sealedIdentity, role: "mac", transcript: keys.transcript, key: keys.replyKey)
        guard trust(mac) else { throw SessionError.untrustedPeer }
        self.keys = keys
        let finish = HandshakeMessage.Finish(sealedIdentity: try SignedIdentity.seal(identity, role: "console",
                                                                                     transcript: keys.transcript, key: keys.finishKey,
                                                                                     chain: chain))
        return (finish, SecureChannel(sendKey: keys.consoleToMac, receiveKey: keys.macToConsole), mac)
    }
}

/// The Mac's side: it answers a console's Hello.
public struct MacHandshake {
    private let identity: DeviceIdentity
    private let ephemeral = Curve25519.KeyAgreement.PrivateKey()
    private var keys: HandshakeKeys?

    public init(identity: DeviceIdentity) {
        self.identity = identity
    }

    public mutating func reply(to hello: HandshakeMessage.Hello) throws -> HandshakeMessage.Reply {
        guard keys == nil else { throw SessionError.unexpectedMessage }
        guard hello.version == HandshakeMessage.version else { throw SessionError.unsupportedVersion(hello.version) }
        guard let consoleKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: hello.ephemeralKey),
              let shared = try? ephemeral.sharedSecretFromKeyAgreement(with: consoleKey) else { throw SessionError.invalidKey }
        let keys = HandshakeKeys(shared: shared, consoleKey: hello.ephemeralKey, macKey: ephemeral.publicKey.rawRepresentation)
        self.keys = keys
        return HandshakeMessage.Reply(ephemeralKey: ephemeral.publicKey.rawRepresentation,
                                      sealedIdentity: try SignedIdentity.seal(identity, role: "mac", transcript: keys.transcript,
                                                                              key: keys.replyKey))
    }

    /// Checks the console's identity with `trust` (is it a paired console?) and returns the channel and the console.
    public func accept(_ finish: HandshakeMessage.Finish, trust: (PublicIdentity) -> Bool) throws
        -> (channel: SecureChannel, console: PublicIdentity) {
        let accepted = try accept(finish, trustChain: { identity, _ in trust(identity) })
        return (accepted.channel, accepted.console)
    }

    /// Like `accept(_:trust:)`, also handing `trustChain` the console's workspace chain when it sent one. The identity
    /// has already proved it holds its key; the chain still has to be checked against the pinned workspace.
    public func accept(_ finish: HandshakeMessage.Finish, trustChain: (PublicIdentity, WorkspaceChain?) -> Bool) throws
        -> (channel: SecureChannel, console: PublicIdentity, chain: WorkspaceChain?) {
        guard let keys else { throw SessionError.unexpectedMessage }
        let signed = try SignedIdentity.openSigned(finish.sealedIdentity, role: "console", transcript: keys.transcript,
                                                   key: keys.finishKey)
        guard trustChain(signed.identity, signed.chain) else { throw SessionError.untrustedPeer }
        return (SecureChannel(sendKey: keys.macToConsole, receiveKey: keys.consoleToMac), signed.identity, signed.chain)
    }
}
