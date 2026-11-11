import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Adding a Mac to a MacPeek Remote account from the Mac itself, for a Mac that is not on the same network as a console
/// (macpeek-remote docs/ACCOUNTS.md §5.4, cloud/src/joins.ts):
///
/// 1. The Mac asks the service, signing its key, its name and a commitment to a random nonce (`requestMessage`).
/// 2. Its person signs in on the web and attaches the request to their account.
/// 3. A console of the account approves, sending the workspace grant and a nonce of its own.
/// 4. The Mac reveals its nonce. Both screens show `words(…)`, made from the Mac's key, the workspace key and both nonces.
/// 5. The person compares them and chooses Join on the Mac, which pins the workspace key and sends its claim.
///
/// The service only carries messages. Each side's nonce is fixed before it learns the other side's choices, so the
/// service cannot pick keys that make the two screens show the same words while handing either side a key of its own.
public enum AccountJoin {
    /// A new random nonce (32 bytes).
    public static func newNonce() -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }

    /// What the Mac sends before revealing its nonce: its SHA-256.
    public static func commitment(to nonce: Data) -> Data {
        Data(SHA256.hash(data: nonce))
    }

    /// The text the Mac signs to ask (macpeek-remote cloud/src/crypto.ts, `joinRequestMessage`).
    public static func requestMessage(macKey: Data, name: String, commitment: Data, time: Int64) throws -> String {
        try SignedText.join(["macpeek-join-request-v1", macKey.base64EncodedString(), name, commitment.base64EncodedString(),
                             String(time)])
    }

    /// The Mac's signed request.
    public static func request(by mac: DeviceIdentity, name: String, commitment: Data, time: Int64) throws -> Data {
        let text = try requestMessage(macKey: mac.publicIdentity.signingKey, name: name, commitment: commitment, time: time)
        return try mac.signature(for: Data(text.utf8))
    }

    /// The four words both screens show before the Mac joins.
    public static func words(macKey: Data, workspaceKey: Data, macNonce: Data, consoleNonce: Data) -> [String] {
        let text = ["macpeek-join-words-v1", macKey.base64EncodedString(), workspaceKey.base64EncodedString(),
                    macNonce.base64EncodedString(), consoleNonce.base64EncodedString()].joined(separator: "\n")
        return MatchingWords.words(for: Data(SHA256.hash(data: Data(text.utf8))))
    }
}
