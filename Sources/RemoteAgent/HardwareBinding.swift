import Foundation
#if canImport(IOKit)
import IOKit
#endif

/// Ties this Mac's identity key to the hardware it was made on.
///
/// The key lives in the login Keychain, which Migration Assistant and Time Machine restores copy to a new Mac. Without
/// this, a Mac set up from another one would carry the same key: the account would see one Mac, and a join from the new
/// one would only refresh the old one's entry. The key is saved with the hardware UUID it was made on; a key found on
/// other hardware was copied, and this Mac makes its own.
public enum HardwareBinding {
    public enum Decision: Equatable, Sendable {
        /// The key was made here (or this Mac's hardware cannot be read): use it.
        case keep
        /// A key from before the binding: made here as far as anyone can tell, so keep it and record this hardware.
        case bind(String)
        /// The key was made on other hardware and copied here: make a new one, bound to this hardware.
        case replace(String)
    }

    /// What to do with a stored key bound to `stored` (nil: saved before the binding) on hardware `current` (nil: unknown).
    public static func decide(stored: String?, current: String?) -> Decision {
        guard let current, !current.isEmpty else { return .keep }
        guard let stored, !stored.isEmpty else { return .bind(current) }
        return stored == current ? .keep : .replace(current)
    }

    /// This Mac's hardware UUID (`IOPlatformUUID`, as System Information shows it), or nil where it cannot be read.
    public static func currentID() -> String? {
        #if canImport(IOKit) && os(macOS)
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(service, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)
        return (value?.takeRetainedValue() as? String).flatMap { $0.isEmpty ? nil : $0 }
        #else
        return nil
        #endif
    }
}
