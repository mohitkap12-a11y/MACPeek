import Foundation

/// How a Mac proves itself to the MacPeek Remote relay ("Allow from anywhere"). The relay sends a fresh challenge on
/// every connection; the Mac signs it with its own identity key, so a recorded answer is worth nothing later. The relay
/// then checks that the key is in a MacPeek Remote account. This only opens the Mac's connection to the relay: each
/// console that comes through it still runs the same end-to-end handshake as on the local network.
public enum RelayAuth {
    /// The Mac's id at the relay and the service: the hex SHA-256 of its Ed25519 public key.
    public static func macID(of signingKey: Data) -> String {
        Digest.sha256Hex(signingKey)
    }

    /// The exact text the relay checks (macpeek-remote cloud/src/crypto.ts, `relayMacMessage`).
    public static func message(macID: String, nonce: String) throws -> String {
        try SignedText.join(["macpeek-relay-mac-v1", macID, nonce])
    }

    /// The answer to the relay's challenge: the Mac's public key and its signature over `message`.
    public static func answer(nonce: String, by mac: DeviceIdentity) throws -> (macKey: Data, signature: Data) {
        let key = mac.publicIdentity.signingKey
        let text = try message(macID: macID(of: key), nonce: nonce)
        return (key, try mac.signature(for: Data(text.utf8)))
    }

    public static func isValid(signature: Data, macKey: Data, nonce: String) -> Bool {
        guard let text = try? message(macID: macID(of: macKey), nonce: nonce) else { return false }
        return SignedText.isValid(signature, of: text, by: macKey)
    }
}
