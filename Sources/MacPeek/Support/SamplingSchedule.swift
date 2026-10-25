#if os(macOS)
import Foundation

/// How long a sampling screen waits before its next sample. Rates need two samples, so the first one is only a
/// baseline: the second follows almost at once and values appear right away; after that the screen samples at the
/// refresh interval chosen in Settings.
enum SamplingSchedule {
    static let quickSecondSample: TimeInterval = 0.4

    /// The wait after sample number `count` (1 for the first).
    static func delay(afterSample count: Int, interval: TimeInterval) -> TimeInterval {
        count <= 1 ? min(quickSecondSample, interval) : interval
    }

    static func nanoseconds(_ seconds: TimeInterval) -> UInt64 { UInt64(max(seconds, 0.1) * 1_000_000_000) }
}
#endif
