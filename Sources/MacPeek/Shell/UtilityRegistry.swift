#if os(macOS)
import Foundation
import MacPeekCore

/// Owns the utility modules and which of them the user has switched on.
/// A disabled utility is never summarized, shown or started: it does no work at all.
@MainActor
final class UtilityRegistry: ObservableObject {
    static let defaultsKey = "disabledUtilities"

    @Published private(set) var selection: UtilitySelection
    @Published private(set) var summaries: [String: String] = [:]

    private let modules: [String: UtilityModule]
    private let defaults: UserDefaults

    init(modules: [UtilityModule], defaults: UserDefaults = .standard) {
        self.modules = Dictionary(uniqueKeysWithValues: modules.map { ($0.info.id, $0) })
        self.defaults = defaults
        self.selection = UtilitySelection(storedDisabled: defaults.stringArray(forKey: Self.defaultsKey))
    }

    func isEnabled(_ id: String) -> Bool { selection.isEnabled(id) && modules[id] != nil }

    /// The module, only if it is enabled.
    func module(for id: String) -> UtilityModule? { isEnabled(id) ? modules[id] : nil }

    /// The module regardless of enabled state (used to stop work when leaving a screen).
    func anyModule(for id: String) -> UtilityModule? { modules[id] }

    /// Enabled utilities that have a module, in catalog order.
    var enabledUtilities: [UtilityInfo] { selection.enabledUtilities.filter { modules[$0.id] != nil } }

    func setEnabled(_ id: String, _ enabled: Bool) {
        var updated = selection
        guard updated.setEnabled(id, enabled) else { return }
        if !enabled {
            modules[id]?.didDisappear()
            summaries[id] = nil
        }
        selection = updated
        defaults.set(updated.storageValue, forKey: Self.defaultsKey)
        if enabled { Task { await refreshSummary(id) } }
    }

    func refreshSummaries() async {
        for info in enabledUtilities { await refreshSummary(info.id) }
    }

    private func refreshSummary(_ id: String) async {
        guard let module = module(for: id) else { return }
        summaries[id] = await module.launcherSummary()
    }
}
#endif
