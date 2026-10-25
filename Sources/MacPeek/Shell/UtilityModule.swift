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
    /// Utilities with a ring tile at the top of the launcher, in this order (CPU, Memory, Disk). Nil: a plain tile.
    var gaugeOrder: Int? { get }
    /// One-shot reading for the ring tile, taken when the popover opens. Must be cheap and must not start polling.
    func launcherGauge() async -> LauncherGauge?
    /// The utility screen became visible: start refreshing/sampling.
    func didAppear()
    /// The screen was left, the utility was disabled, or the popover closed: stop all expensive work.
    func didDisappear()
    func makeView() -> AnyView
}

extension UtilityModule {
    func launcherSummary() async -> String? { nil }
    var gaugeOrder: Int? { nil }
    func launcherGauge() async -> LauncherGauge? { nil }
    func didAppear() {}
    func didDisappear() {}
}

/// What a ring tile in the launcher shows: "38%" in the ring, "load 4.12" under the name.
struct LauncherGauge: Equatable {
    enum Tint: Equatable { case accent, amber, red }

    let fraction: Double
    let value: String
    let caption: String
    var tint: Tint = .accent
}

extension LauncherGauge {
    /// A ring in the utility's own colour, red when the reading is an alert.
    init(_ reading: GaugeReading, tint: Tint) {
        self.init(fraction: reading.fraction, value: reading.value, caption: reading.caption, tint: reading.isAlert ? .red : tint)
    }
}
#endif
