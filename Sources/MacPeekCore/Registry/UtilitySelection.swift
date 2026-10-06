import Foundation

/// Which utilities the user has switched on. Persists the *disabled* set, so a utility that ships in a
/// later version appears enabled by default instead of being hidden by a stale "enabled" list.
/// A utility that is not yet available can never be enabled.
public struct UtilitySelection: Equatable, Sendable {
    public private(set) var disabled: Set<String>
    private let catalog: [UtilityInfo]

    public init(disabled: Set<String> = [], catalog: [UtilityInfo] = UtilityCatalog.all) {
        self.disabled = disabled
        self.catalog = catalog
    }

    public init(storedDisabled: [String]?, catalog: [UtilityInfo] = UtilityCatalog.all) {
        self.init(disabled: Set(storedDisabled ?? []), catalog: catalog)
    }

    public func isEnabled(_ id: String) -> Bool {
        guard let info = catalog.first(where: { $0.id == id }) else { return false }
        return info.isAvailable && !disabled.contains(id)
    }

    /// Returns false (and changes nothing) if the utility is unknown or not available yet.
    @discardableResult
    public mutating func setEnabled(_ id: String, _ enabled: Bool) -> Bool {
        guard let info = catalog.first(where: { $0.id == id }), info.isAvailable else { return false }
        if enabled { disabled.remove(id) } else { disabled.insert(id) }
        return true
    }

    /// Enabled utilities in catalog order.
    public var enabledUtilities: [UtilityInfo] { catalog.filter { isEnabled($0.id) } }
    public var enabledCount: Int { enabledUtilities.count }
    public var availableCount: Int { catalog.filter(\.isAvailable).count }

    /// Stable form for UserDefaults.
    public var storageValue: [String] { disabled.sorted() }
}
