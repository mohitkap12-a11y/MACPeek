import Foundation

/// Adding a Mac to a MacPeek Remote account, the only way a Mac joins one (macpeek-remote docs/ACCOUNTS.md §5.3a,
/// cloud/src/joins.ts):
///
/// 1. The Mac asks the service, signing its key, its name and the time (`requestMessage`), and opens the account site.
/// 2. Its person signs in there and adds it to their account.
/// 3. MacPeek Remote, signed in to that account on their main Mac, approves it, sending the account's grant.
/// 4. The Mac checks the grant, sends its claim and joins: it pins the account key, and from then on only devices whose
///    certificate chain leads to that key connect.
///
/// The service is trusted to hand the Mac the grant the console sent: whoever controlled it while a Mac joins could give
/// that Mac a key of its own. Once joined, the Mac keeps the key it pinned.
public enum AccountJoin {
    /// The text the Mac signs to ask (macpeek-remote cloud/src/crypto.ts, `joinRequestMessage`).
    public static func requestMessage(macKey: Data, name: String, time: Int64) throws -> String {
        try SignedText.join(["macpeek-join-request-v1", macKey.base64EncodedString(), name, String(time)])
    }

    /// The Mac's signed request.
    public static func request(by mac: DeviceIdentity, name: String, time: Int64) throws -> Data {
        let text = try requestMessage(macKey: mac.publicIdentity.signingKey, name: name, time: time)
        return try mac.signature(for: Data(text.utf8))
    }
}
