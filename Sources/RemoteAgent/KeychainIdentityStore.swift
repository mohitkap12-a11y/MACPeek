#if canImport(Security)
import Foundation
import Security
import RemoteCrypto

/// Keeps this Mac's long-term identity key in the login Keychain, readable only by MacPeek on this device.
public struct KeychainIdentityStore: Sendable {
    public enum Error: Swift.Error, Equatable { case keychain(OSStatus) }

    public let service: String
    public let account: String

    public init(service: String = "com.macpeek.remote", account: String = "agent-identity") {
        self.service = service
        self.account = account
    }

    /// The stored identity, or a new one saved for next time.
    public func loadOrCreate(name: String) throws -> DeviceIdentity {
        if let data = try load(), let identity = try? DeviceIdentity(name: name, privateKeyData: data) { return identity }
        let identity = DeviceIdentity(name: name)
        try save(identity.privateKeyData)
        return identity
    }

    /// Removes the key, so the next start makes a new identity and every console has to pair again.
    public func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Error.keychain(status) }
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    private func load() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Error.keychain(status) }
        return result as? Data
    }

    private func save(_ data: Data) throws {
        try delete()
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw Error.keychain(status) }
    }
}
#endif
