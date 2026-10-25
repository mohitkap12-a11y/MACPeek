import Foundation
import MacPeekCore

/// Plain-language reading of the numbers. It leads with memory pressure, because a Mac whose memory looks "full" is
/// usually fine: macOS keeps spare memory busy with cached files.
public struct MemoryAssessment: Equatable, Sendable {
    public enum Tone: Equatable, Sendable { case good, warning, critical, unknown }

    public let tone: Tone
    public let headline: String
    public let detail: [String]

    public init(stats: MemoryStats) {
        let breakdown = MemoryBreakdown(stats)
        var detail: [String] = []
        switch stats.pressure {
        case .normal:
            tone = .good
            headline = "Memory is fine"
            detail.append("Memory pressure is normal. macOS keeps unused memory busy with cached files on purpose and gives it back as soon as an app needs it.")
        case .warning:
            tone = .warning
            headline = "Memory is getting tight"
            detail.append("macOS is compressing memory and may start moving some of it to disk. Quitting apps you are not using frees memory fastest.")
        case .critical:
            tone = .critical
            headline = "Your Mac is short of memory"
            detail.append("Memory pressure is critical, so apps can slow down. Quit apps you are not using; the ones using the most memory are listed below.")
        case nil:
            tone = .unknown
            headline = "Memory pressure not reported"
            detail.append("macOS did not report memory pressure, so MacPeek cannot say whether memory is short.")
        }
        if let swap = stats.swapUsedBytes, swap > 0 {
            if stats.pressure == .normal {
                detail.append("\(ByteCountText.memory(swap)) was moved to disk (swap) earlier. That is normal while pressure stays normal.")
            } else {
                detail.append("\(ByteCountText.memory(swap)) of memory has been moved to disk (swap), which is slower than RAM.")
            }
        }
        if breakdown.cachedFiles > 0, stats.pressure == .normal, breakdown.free < breakdown.physical / 10 {
            detail.append("Little memory is completely free, but \(ByteCountText.memory(breakdown.cachedFiles)) holds cached files that macOS can reuse.")
        }
        self.detail = detail
    }

    /// The short launcher line, e.g. "Pressure: Normal".
    public static func launcherSummary(_ stats: MemoryStats) -> String? {
        stats.pressure.map { "Pressure: \($0.rawValue)" }
    }

    /// Processes using the most memory, largest first (ties by PID so the order is stable).
    public static func topProcesses(_ usages: [ProcessUsage], limit: Int = 15) -> [ProcessMemoryRow] {
        let rows = usages.filter { $0.memoryFootprintBytes > 0 }
            .map { ProcessMemoryRow(pid: $0.pid, name: $0.name, footprintBytes: $0.memoryFootprintBytes) }
            .sorted { ($0.footprintBytes, $1.pid) > ($1.footprintBytes, $0.pid) }
        return Array(rows.prefix(limit))
    }
}
