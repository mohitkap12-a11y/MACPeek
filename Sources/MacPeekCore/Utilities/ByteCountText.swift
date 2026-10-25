import Foundation

/// The one byte formatter every utility uses: one decimal below 100, none from 100 up, e.g. "1.5 KB", "23.4 MB",
/// "150 MB". Rounding happens before the unit is chosen, so 999.97 never prints as "1000".
public enum ByteCountText {
    /// Binary units (1 KB = 1024 B), as Activity Monitor shows memory and I/O: 17_179_869_184 → "16.0 GB".
    public static func memory(_ bytes: UInt64) -> String { binary(Double(bytes)) }

    /// Binary units for fractional values such as rates.
    public static func binary(_ bytes: Double) -> String { label(bytes, base: 1024) }

    /// Decimal units (1 KB = 1000 B), as Finder shows storage: 1_000_000_000_000 → "1.0 TB".
    public static func storage(_ bytes: Int64) -> String { label(Double(max(bytes, 0)), base: 1000) }

    private static let units = ["B", "KB", "MB", "GB", "TB", "PB"]

    private static func label(_ bytes: Double, base: Double) -> String {
        var value = bytes.isFinite ? max(bytes, 0) : 0
        var index = 0
        while value >= base && index < units.count - 1 {
            value /= base
            index += 1
        }
        var (rounded, decimals) = roundForDisplay(value, unitIndex: index)
        if rounded >= base && index < units.count - 1 {
            value /= base
            index += 1
            (rounded, decimals) = roundForDisplay(value, unitIndex: index)
        }
        return decimals == 0 ? "\(Int(rounded)) \(units[index])" : String(format: "%.1f %@", rounded, units[index])
    }

    /// Bytes are whole numbers; other units keep one decimal until the rounded value reaches 100.
    private static func roundForDisplay(_ value: Double, unitIndex: Int) -> (Double, Int) {
        if unitIndex == 0 { return (value.rounded(), 0) }
        let tenths = (value * 10).rounded() / 10
        return tenths >= 100 ? (value.rounded(), 0) : (tenths, 1)
    }
}
