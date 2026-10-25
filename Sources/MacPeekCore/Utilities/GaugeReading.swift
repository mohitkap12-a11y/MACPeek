import Foundation

/// What a launcher ring shows for a utility: "38%" in the ring and "load 4.12" under its name. `isAlert` turns the ring
/// red (critical memory pressure, a hot CPU, a nearly full startup disk).
public struct GaugeReading: Equatable, Sendable {
    public let fraction: Double
    public let value: String
    public let caption: String
    public let isAlert: Bool

    public init(fraction: Double, caption: String, isAlert: Bool = false) {
        self.fraction = min(max(fraction, 0), 1)
        self.value = "\(Int((self.fraction * 100).rounded()))%"
        self.caption = caption
        self.isAlert = isAlert
    }
}
