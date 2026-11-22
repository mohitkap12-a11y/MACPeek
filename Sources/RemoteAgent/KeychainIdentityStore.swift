#if canImport(Security)
import Foundation
import Security
import RemoteCrypto

/// Keeps this Mac's long-term identity key in the login Keychain, readable only by MacPeek on this device.
///
/// The login Keychain moves to a new Mac with Migration Assistant or a Time Machine restore, whatever its accessibility
/// says, so the key is saved with the hardware UUID it was made on (`HardwareBinding`). A key found on other hardware
/// was copied from the old Mac: this Mac makes its own, so the two never share an identity.
public struct KeychainIdentityStore: Sendable {
    public enum Error: Swift.Error, Equatable { case keychain(OSStatus) }

    /// The identity to use, and whether the one stored was another Mac's (copied here) and has just been replaced.
    public struct Loaded {
        public let identity: DeviceIdentity
        public let replacedCopiedIdentity: Bool
    }

    public let service: String
    public let account: String
    private let hardwareID: @Sendable () -> String?

    public init(service: String = "com.macpeek.remote", account: String = "agent-identity",
                hardwareID: @escaping @Sendable () -> String? = HardwareBinding.currentID) {
        self.service = service
        self.account = account
        self.hardwareID = hardwareID
    }

    /// The stored identity, or a new one saved for next time.
    public func loadOrCreate(name: String) throws -> DeviceIdentity {
        try loadOrCreateForThisMac(name: name).identity
    }

    /// The stored identity if it was made on this Mac, else a new one saved for next time.
    ///
    /// `beforeReplacing` runs when the stored key was copied from another Mac, before the new key is saved: it clears
    /// what came with the copy (its account). If it throws, the copied key stays, so the next launch tries again; once
    /// the new key is saved, it counts as this Mac's and nothing would retry.
    public func loadOrCreateForThisMac(name: String, beforeReplacing: () throws -> Void = {}) throws -> Loaded {
        let current = hardwareID()
        if let stored = try load(), let identity = try? DeviceIdentity(name: name, privateKeyData: stored.key) {
            switch HardwareBinding.decide(stored: stored.hardware, current: current) {
            case .keep:
                return Loaded(identity: identity, replacedCopiedIdentity: false)
            case .bind(let hardware):
                // Saved before the binding: record this Mac, keeping the key (and every console that knows it).
                try? bind(to: hardware)
                return Loaded(identity: identity, replacedCopiedIdentity: false)
            case .replace(let hardware):
                try beforeReplacing()
                let fresh = DeviceIdentity(name: name)
                try save(fresh.privateKeyData, hardware: hardware)
                return Loaded(identity: fresh, replacedCopiedIdentity: true)
            }
        }
        let identity = DeviceIdentity(name: name)
        try save(identity.privateKeyData, hardware: current)
        return Loaded(identity: identity, replacedCopiedIdentity: false)
    }

    /// Removes the key, so the next start makes a new identity and every console has to pair again.
    public func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Error.keychain(status) }
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    private func load() throws -> (key: Data, hardware: String?)? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let item = result as? [String: Any], let key = item[kSecValueData as String] as? Data else {
            throw Error.keychain(status == errSecSuccess ? errSecInternalError : status)
        }
        let hardware = (item[kSecAttrGeneric as String] as? Data).map { String(decoding: $0, as: UTF8.self) }
        return (key, hardware)
    }

    private func bind(to hardware: String) throws {
        let change = [kSecAttrGeneric as String: Data(hardware.utf8)]
        let status = SecItemUpdate(baseQuery as CFDictionary, change as CFDictionary)
        guard status == errSecSuccess else { throw Error.keychain(status) }
    }

    private func save(_ data: Data, hardware: String?) throws {
        try delete()
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        if let hardware { query[kSecAttrGeneric as String] = Data(hardware.utf8) }
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw Error.keychain(status) }
    }
}
#endif
