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
    @Published private(set) var gauges: [String: LauncherGauge] = [:]

    private let modules: [String: UtilityModule]
    private let defaults: UserDefaults
    /// Seconds between ring updates while the launcher is on screen (the refresh interval from Settings).
    var gaugeRefreshInterval: @MainActor () -> TimeInterval = { 2 }
    /// Keeps the launcher rings live while the launcher is visible; nil otherwise.
    private var gaugeTask: Task<Void, Never>?
    /// In-flight launcher-summary tasks, so they can be cancelled when a utility is disabled or the popover closes.
    private var summaryTasks: [String: Task<Void, Never>] = [:]

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

    /// Enabled utilities shown as ring tiles at the top of the launcher, in their gauge order.
    var gaugeUtilities: [UtilityInfo] {
        enabledUtilities.filter { modules[$0.id]?.gaugeOrder != nil }
            .sorted { (modules[$0.id]?.gaugeOrder ?? 0) < (modules[$1.id]?.gaugeOrder ?? 0) }
    }

    /// Enabled utilities listed as rows under the rings, in catalog order.
    var tileUtilities: [UtilityInfo] { enabledUtilities.filter { modules[$0.id]?.gaugeOrder == nil } }

    func setEnabled(_ id: String, _ enabled: Bool) {
        var updated = selection
        guard updated.setEnabled(id, enabled) else { return }
        if !enabled {
            summaryTasks[id]?.cancel()
            summaryTasks[id] = nil
            modules[id]?.didDisappear()
            summaries[id] = nil
            gauges[id] = nil
        }
        selection = updated
        defaults.set(updated.storageValue, forKey: Self.defaultsKey)
        if enabled { startSummary(id) }
    }

    /// Starts one tracked, cancellable summary task per enabled utility.
    func refreshSummaries() {
        for info in enabledUtilities { startSummary(info.id) }
    }

    /// Updates the CPU, Memory and Disk rings at the refresh interval while the launcher is on screen. Each update is
    /// the same cheap one-shot reading as when the popover opens; nothing runs once the launcher is left or closed.
    /// `immediately` reads the rings at once (returning to the launcher) instead of after one interval (the popover
    /// just opened and `refreshSummaries()` is already reading them).
    func startGaugeUpdates(immediately: Bool = false) {
        stopGaugeUpdates()
        gaugeTask = Task { [weak self] in
            var wait = !immediately
            while !Task.isCancelled {
                if wait {
                    guard let seconds = self?.gaugeRefreshInterval() else { return }
                    try? await Task.sleep(nanoseconds: UInt64(max(seconds, 1) * 1_000_000_000))
                }
                wait = true
                guard let self, !Task.isCancelled else { return }
                for info in self.gaugeUtilities {
                    guard let module = self.module(for: info.id) else { continue }
                    let gauge = await module.launcherGauge()
                    guard !Task.isCancelled else { return }
                    // A failed read keeps the last value rather than blanking the ring.
                    if let gauge, self.isEnabled(info.id) { self.gauges[info.id] = gauge }
                }
            }
        }
    }

    func stopGaugeUpdates() {
        gaugeTask?.cancel()
        gaugeTask = nil
    }

    /// Cancels in-flight summary work (popover closed). Cancellation reaches `lsof` via `ShellCommand`.
    func cancelSummaries() {
        for task in summaryTasks.values { task.cancel() }
        summaryTasks.removeAll()
    }

    private func startSummary(_ id: String) {
        summaryTasks[id]?.cancel()
        guard let module = module(for: id) else { return }
        summaryTasks[id] = Task { [weak self] in
            let summary = await module.launcherSummary()
            let gauge = await module.launcherGauge()
            // Drop the result if we were cancelled or the utility was disabled while it ran.
            guard let self, !Task.isCancelled, self.isEnabled(id) else { return }
            self.summaries[id] = summary
            self.gauges[id] = gauge
        }
    }
}
#endif
