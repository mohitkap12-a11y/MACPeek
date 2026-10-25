import Foundation

/// Byte counts as people read them elsewhere on macOS.
public enum ByteCountText {
    /// Binary units (1 KB = 1024 B), as Activity Monitor shows memory: 17_179_869_184 → "16.0 GB".
    public static func memory(_ bytes: UInt64) -> String { label(Double(bytes), base: 1024) }

    /// Decimal units (1 KB = 1000 B), as Finder shows storage: 1_000_000_000_000 → "1.00 TB".
    public static func storage(_ bytes: Int64) -> String { label(Double(max(bytes, 0)), base: 1000) }

    private static func label(_ bytes: Double, base: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var value = max(bytes, 0)
        var index = 0
        while value >= base && index < units.count - 1 {
            value /= base
            index += 1
        }
        if index == 0 { return "\(Int(value)) B" }
        if value >= 100 { return String(format: "%.0f %@", value, units[index]) }
        if value >= 10 { return String(format: "%.1f %@", value, units[index]) }
        return String(format: "%.2f %@", value, units[index])
    }
}
