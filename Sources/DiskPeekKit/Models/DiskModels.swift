import Foundation

/// Cumulative disk I/O counters macOS keeps for one process since it started.
public struct DiskCounters: Equatable, Sendable {
    public let pid: Int
    public let name: String
    public let bytesRead: UInt64
    public let bytesWritten: UInt64
    /// Identifies *which* process currently holds the PID (its start time as the OS reports it). A PID that comes
    /// back with a different generation is a different process, even if its counters happen to be higher. Zero
    /// means "unknown", in which case only a counter that goes down reveals a reused PID.
    public let generation: UInt64

    public init(pid: Int, name: String, bytesRead: UInt64, bytesWritten: UInt64, generation: UInt64 = 0) {
        self.pid = pid
        self.name = name
        self.bytesRead = bytesRead
        self.bytesWritten = bytesWritten
        self.generation = generation
    }
}

/// A flag a synchronous reader polls so that cancelling the surrounding task can stop a scan that is already running.
public final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    public func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}

public struct DiskReadResult: Equatable, Sendable {
    public let counters: [DiskCounters]
    /// Processes whose counters macOS would not give us (other users' processes).
    public let unreadable: Int

    public init(counters: [DiskCounters], unreadable: Int) {
        self.counters = counters
        self.unreadable = unreadable
    }
}

/// What one process did between two samples. Every value is *sampled*: an estimate over the sampling interval.
public struct DiskActivity: Identifiable, Equatable, Sendable {
    public var id: Int { pid }
    public let pid: Int
    public let name: String
    public let readBytesPerSecond: Double
    public let writeBytesPerSecond: Double
    /// Bytes read / written since DiskPeek was opened (or since the process first appeared).
    public let readSinceOpened: UInt64
    public let writtenSinceOpened: UInt64

    public init(pid: Int, name: String, readBytesPerSecond: Double, writeBytesPerSecond: Double,
                readSinceOpened: UInt64, writtenSinceOpened: UInt64) {
        self.pid = pid
        self.name = name
        self.readBytesPerSecond = readBytesPerSecond
        self.writeBytesPerSecond = writeBytesPerSecond
        self.readSinceOpened = readSinceOpened
        self.writtenSinceOpened = writtenSinceOpened
    }

    public var totalBytesPerSecond: Double { readBytesPerSecond + writeBytesPerSecond }
    public var totalSinceOpened: UInt64 { readSinceOpened &+ writtenSinceOpened }
}

public enum DiskSort: String, CaseIterable, Sendable {
    case rate = "Right now"
    case total = "Since opened"
}

public enum ByteRate {
    /// 1_500_000 → "1.4 MB/s"; 0 → "0 B/s". Binary units, like Activity Monitor.
    public static func label(_ bytesPerSecond: Double) -> String { ByteSize.label(bytesPerSecond) + "/s" }
}

public enum ByteSize {
    public static func label(_ bytes: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = max(bytes, 0)
        var index = 0
        while value >= 1024 && index < units.count - 1 {
            value /= 1024
            index += 1
        }
        if index == 0 { return "\(Int(value)) B" }
        return value >= 100 ? String(format: "%.0f %@", value, units[index]) : String(format: "%.1f %@", value, units[index])
    }
}
