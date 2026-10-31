import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

// Pairing a console with a Mac, once, in four messages:
//
//   console → Mac   Start    commitment to the console's one-time key (a hash of it, not the key itself)
//   Mac → console   Accept   the Mac's one-time key
//   console → Mac   Reveal   the console's one-time key, plus proof that the console knows the code shown on the Mac
//   both            Confirm  each side's long-term identity, signed over this session and encrypted
//
// Both screens show four words derived from the session. They match only if nobody is in the middle. Because the
// console commits to its key before seeing the Mac's, an attacker in the middle cannot try keys until the words happen
// to match: they get one 1-in-4-billion guess per attempt, and every attempt uses up the code. Each side sends Confirm
// only after its person has checked the words, and pins the other side's identity only after verifying its Confirm.

public enum PairingError: Error, Equatable, Sendable {
    case unexpectedMessage
    case unsupportedVersion(Int)
    case invalidKey
    case commitmentMismatch
    case wrongCode
    case codeExpired
    case tooManyAttempts
    case invalidIdentity
}

public enum PairingMessage {
    public static let version = 1

    public struct Start: Equatable, Codable, Sendable {
        public let version: Int
        public let commitment: Data
    }

    public struct Accept: Equatable, Codable, Sendable {
        public let ephemeralKey: Data
        public let nonce: Data
    }

    public struct Reveal: Equatable, Codable, Sendable {
        public let ephemeralKey: Data
        public let nonce: Data
        public let codeProof: Data
    }

    public struct Confirm: Equatable, Codable, Sendable {
        /// ChaCha20-Poly1305 box (nonce + ciphertext + tag) holding a signed `IdentityProof`.
        public let sealedIdentity: Data
    }
}

/// Keys and words for one pairing session, derived identically on both sides.
struct PairingSecrets {
    let transcript: Data
    let words: [String]
    let consoleToMac: SymmetricKey
    let macToConsole: SymmetricKey
    private let shared: SharedSecret

    init(shared: SharedSecret, commitment: Data, accept: PairingMessage.Accept, consoleKey: Data, consoleNonce: Data) {
        var transcript = Data("macpeek-pair-v1".utf8)
        for part in [commitment, accept.ephemeralKey, accept.nonce, consoleKey, consoleNonce] { transcript.append(part) }
        let hash = Data(SHA256.hash(data: transcript))
        self.transcript = hash
        self.shared = shared
        consoleToMac = Self.key(shared, hash, "console to mac")
        macToConsole = Self.key(shared, hash, "mac to console")
        words = MatchingWords.words(for: Self.key(shared, hash, "matching words").withUnsafeBytes { Data($0) })
    }

    func codeProof(code: String) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: transcript, using: Self.key(shared, transcript, "code " + code)))
    }

    func isValidCodeProof(_ proof: Data, code: String) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(proof, authenticating: transcript, using: Self.key(shared, transcript, "code " + code))
    }

    private static func key(_ shared: SharedSecret, _ salt: Data, _ info: String) -> SymmetricKey {
        shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: Data(info.utf8), outputByteCount: 32)
    }
}

/// A long-term identity, signed over one session so it cannot be replayed into another. Since protocol version 2 the
/// console may add a workspace grant (pin this account, not only me) and the Mac its claim; both travel inside the
/// box, which only the two sides of this pairing can seal or open. Older apps ignore the fields they do not know.
struct IdentityProof: Codable {
    let identity: PublicIdentity
    let signature: Data
    var grant: WorkspaceGrant?
    var claim: MacClaim?

    static func signedData(role: String, transcript: Data) -> Data { Data("macpeek-identity-v1 \(role)".utf8) + transcript }

    static func seal(_ identity: DeviceIdentity, role: String, transcript: Data, key: SymmetricKey,
                     grant: WorkspaceGrant? = nil, claim: MacClaim? = nil) throws -> PairingMessage.Confirm {
        let proof = IdentityProof(identity: identity.publicIdentity,
                                  signature: try identity.signature(for: signedData(role: role, transcript: transcript)),
                                  grant: grant, claim: claim)
        let box = try ChaChaPoly.seal(try JSONEncoder().encode(proof), using: key)
        return PairingMessage.Confirm(sealedIdentity: box.combined)
    }

    static func open(_ confirm: PairingMessage.Confirm, role: String, transcript: Data, key: SymmetricKey) throws -> IdentityProof {
        guard let box = try? ChaChaPoly.SealedBox(combined: confirm.sealedIdentity),
              let plain = try? ChaChaPoly.open(box, using: key),
              let proof = try? JSONDecoder().decode(IdentityProof.self, from: plain),
              proof.identity.isValidSignature(proof.signature, for: signedData(role: role, transcript: transcript)) else {
            throw PairingError.invalidIdentity
        }
        return proof
    }
}

private func randomNonce() -> Data {
    var generator = SystemRandomNumberGenerator()
    return Data((0..<32).map { _ in UInt8.random(in: 0...255, using: &generator) })
}

private func commitment(key: Data, nonce: Data) -> Data {
    Data(SHA256.hash(data: Data("macpeek-pair-commit-v1".utf8) + key + nonce))
}

/// The console's side of pairing.
public struct ConsolePairing {
    private let identity: DeviceIdentity
    private let ephemeral = Curve25519.KeyAgreement.PrivateKey()
    private let nonce = randomNonce()
    private var secrets: PairingSecrets?

    public init(identity: DeviceIdentity) {
        self.identity = identity
    }

    /// The first message.
    public func start() -> PairingMessage.Start {
        PairingMessage.Start(version: PairingMessage.version,
                             commitment: commitment(key: ephemeral.publicKey.rawRepresentation, nonce: nonce))
    }

    /// Answers the Mac's Accept with the typed code. Returns the message to send and the words to show.
    public mutating func reveal(after accept: PairingMessage.Accept, code: String) throws -> (reveal: PairingMessage.Reveal, words: [String]) {
        guard secrets == nil else { throw PairingError.unexpectedMessage }
        guard let digits = PairingCode.normalized(code) else { throw PairingError.wrongCode }
        guard accept.nonce.count == 32, let macKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: accept.ephemeralKey),
              let shared = try? ephemeral.sharedSecretFromKeyAgreement(with: macKey) else { throw PairingError.invalidKey }
        let ownKey = ephemeral.publicKey.rawRepresentation
        let secrets = PairingSecrets(shared: shared, commitment: commitment(key: ownKey, nonce: nonce), accept: accept,
                                     consoleKey: ownKey, consoleNonce: nonce)
        self.secrets = secrets
        return (PairingMessage.Reveal(ephemeralKey: ownKey, nonce: nonce, codeProof: secrets.codeProof(code: digits)), secrets.words)
    }

    /// Send this only after the person has confirmed the words match. A console signed in to an account passes its
    /// workspace grant, so a Mac that speaks protocol version 2 pins the account rather than this console alone.
    public func confirm(grant: WorkspaceGrant? = nil) throws -> PairingMessage.Confirm {
        guard let secrets else { throw PairingError.unexpectedMessage }
        return try IdentityProof.seal(identity, role: "console", transcript: secrets.transcript, key: secrets.consoleToMac,
                                      grant: grant)
    }

    /// The Mac's identity to pin, once its Confirm checks out.
    public func macIdentity(from confirm: PairingMessage.Confirm) throws -> PublicIdentity {
        try macConfirmation(from: confirm).mac
    }

    /// The Mac's identity and, when it joined the workspace in the grant, its signed claim.
    public func macConfirmation(from confirm: PairingMessage.Confirm) throws -> (mac: PublicIdentity, claim: MacClaim?) {
        guard let secrets else { throw PairingError.unexpectedMessage }
        let proof = try IdentityProof.open(confirm, role: "mac", transcript: secrets.transcript, key: secrets.macToConsole)
        // A claim must be the Mac's own, for a real signature; anything else is ignored rather than trusted.
        let claim = proof.claim.flatMap { $0.isValid && $0.macKey == proof.identity.signingKey ? $0 : nil }
        return (proof.identity, claim)
    }
}

/// The Mac's side of pairing, for one displayed code.
public struct MacPairing {
    private let identity: DeviceIdentity
    /// The code this pairing checks against, so the agent can tell whether it is still the one on screen.
    public let code: PairingCode
    private let ephemeral = Curve25519.KeyAgreement.PrivateKey()
    private let nonce = randomNonce()
    private var start: PairingMessage.Start?
    private var secrets: PairingSecrets?

    public init(identity: DeviceIdentity, code: PairingCode) {
        self.identity = identity
        self.code = code
    }

    public mutating func accept(_ start: PairingMessage.Start, now: Date = Date()) throws -> PairingMessage.Accept {
        guard self.start == nil else { throw PairingError.unexpectedMessage }
        guard start.version == PairingMessage.version else { throw PairingError.unsupportedVersion(start.version) }
        guard !code.isExpired(at: now) else { throw PairingError.codeExpired }
        guard start.commitment.count == 32 else { throw PairingError.invalidKey }
        self.start = start
        return PairingMessage.Accept(ephemeralKey: ephemeral.publicKey.rawRepresentation, nonce: nonce)
    }

    /// Checks the console's key against its commitment and the code proof. Returns the words to show.
    public mutating func words(after reveal: PairingMessage.Reveal, now: Date = Date()) throws -> [String] {
        guard let start, secrets == nil else { throw PairingError.unexpectedMessage }
        guard !code.isExpired(at: now) else { throw PairingError.codeExpired }
        guard reveal.nonce.count == 32, commitment(key: reveal.ephemeralKey, nonce: reveal.nonce) == start.commitment else {
            throw PairingError.commitmentMismatch
        }
        guard let consoleKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: reveal.ephemeralKey),
              let shared = try? ephemeral.sharedSecretFromKeyAgreement(with: consoleKey) else { throw PairingError.invalidKey }
        let accept = PairingMessage.Accept(ephemeralKey: ephemeral.publicKey.rawRepresentation, nonce: nonce)
        let secrets = PairingSecrets(shared: shared, commitment: start.commitment, accept: accept,
                                     consoleKey: reveal.ephemeralKey, consoleNonce: reveal.nonce)
        guard secrets.isValidCodeProof(reveal.codeProof, code: code.digits) else { throw PairingError.wrongCode }
        self.secrets = secrets
        return secrets.words
    }

    /// Send this only after the person at this Mac has confirmed the words match. `claim` is set when this Mac joined
    /// the console's workspace.
    public func confirm(claim: MacClaim? = nil) throws -> PairingMessage.Confirm {
        guard let secrets else { throw PairingError.unexpectedMessage }
        return try IdentityProof.seal(identity, role: "mac", transcript: secrets.transcript, key: secrets.macToConsole,
                                      claim: claim)
    }

    /// The console's identity to pin, once its Confirm checks out.
    public func consoleIdentity(from confirm: PairingMessage.Confirm) throws -> PublicIdentity {
        try consoleConfirmation(from: confirm).console
    }

    /// The console's identity and, from a console signed in to an account, a consistent workspace grant.
    public func consoleConfirmation(from confirm: PairingMessage.Confirm) throws -> (console: PublicIdentity, grant: WorkspaceGrant?) {
        guard let secrets else { throw PairingError.unexpectedMessage }
        let proof = try IdentityProof.open(confirm, role: "console", transcript: secrets.transcript, key: secrets.consoleToMac)
        return (proof.identity, proof.grant.flatMap { $0.isValid() ? $0 : nil })
    }
}
