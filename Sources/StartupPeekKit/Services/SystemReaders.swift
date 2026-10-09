#if canImport(Security)
import Foundation
import Security

/// Reads the signing information of a file or `.app` bundle with the Security framework. Static inspection only: the code
/// is not run, and validity (trust, revocation, tampering) is deliberately not evaluated.
public struct SecurityCodeSignatureReader: CodeSignatureReading {
    public init() {}

    public func signature(atPath path: String) -> SignatureInfo {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode else { return .unavailable }
        var information: CFDictionary?
        let status = SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
        if status == errSecCSUnsigned { return .unsigned }
        guard status == errSecSuccess, let info = information as? [String: Any] else { return .unavailable }
        let team = info[kSecCodeInfoTeamIdentifier as String] as? String
        let identifier = info[kSecCodeInfoIdentifier as String] as? String
        return .signed(teamID: team, identifier: identifier)
    }
}
#endif

#if canImport(ServiceManagement)
import Foundation
import ServiceManagement

/// MacPeek's own login-item state via `SMAppService.mainApp` (macOS 13+), the purpose that API documents.
public struct ServiceManagementOwnLoginItem: OwnLoginItemReading {
    public init() {}

    public func state() -> OwnLoginItemState? {
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled: return .enabled
            case .requiresApproval: return .requiresApproval
            case .notRegistered: return .notRegistered
            case .notFound: return .notFound
            @unknown default: return nil
            }
        }
        return nil
    }
}
#endif
