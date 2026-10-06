#if os(macOS)
import SwiftUI
import MacPeekCore

/// What a utility plugs into the shell. The shell knows only this: metadata, lifecycle and a view.
/// Everything else (models, services, refresh logic) stays inside the utility.
@MainActor
protocol UtilityModule: AnyObject {
    var info: UtilityInfo { get }
    /// One-shot live subtitle for the launcher row, e.g. "8 active". Called when the popover opens.
    /// Must be cheap and must not start polling.
    func launcherSummary() async -> String?
    /// The utility screen became visible: start refreshing/sampling.
    func didAppear()
    /// The screen was left, the utility was disabled, or the popover closed: stop all expensive work.
    func didDisappear()
    func makeView() -> AnyView
}

extension UtilityModule {
    func launcherSummary() async -> String? { nil }
    func didAppear() {}
    func didDisappear() {}
}
#endif
