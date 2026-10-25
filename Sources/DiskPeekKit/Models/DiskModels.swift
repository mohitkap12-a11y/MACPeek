import Foundation
import MacPeekCore

/// Cumulative disk I/O counters macOS keeps for one process since it started.
public struct DiskCounters: Equatable, Codable, Sendable {
    public let pid: Int
    public let name: String
    public let bytesRead: UInt64
    public let bytesWritten: UInt64
    /// Identifies *which* process currently holds the PID (its start time as the OS reports it). A PID that comes
    /// back with a different generation is a different process, even if its counters happen to be higher. Zero
    /// means "unknown", in which case only a counter that goes down reveals a reused PID.
    public let generation: UInt64
    /// How long ago the process started, when known (see `ProcessCounterSampler`).
    public let ageNanoseconds: UInt64?

    public init(pid: Int, name: String, bytesRead: UInt64, bytesWritten: UInt64, generation: UInt64 = 0,
                ageNanoseconds: UInt64? = nil) {
        self.pid = pid
        self.name = name
        self.bytesRead = bytesRead
        self.bytesWritten = bytesWritten
        self.generation = generation
        self.ageNanoseconds = ageNanoseconds
    }
}

public struct DiskReadResult: Equatable, Codable, Sendable {
    public let counters: [DiskCounters]
    /// Processes whose counters macOS would not give us (other users' processes).
    public let unreadable: Int

    public init(counters: [DiskCounters], unreadable: Int) {
        self.counters = counters
        self.unreadable = unreadable
    }
}

/// What one process did between two samples. Every value is *sampled*: an estimate over the sampling interval.
public struct DiskActivity: Identifiable, Equatable, Codable, Sendable {
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
    public static func label(_ bytesPerSecond: Double) -> String { ByteCountText.binary(bytesPerSecond) + "/s" }
}

public enum ByteSize {
    public static func label(_ bytes: Double) -> String { ByteCountText.binary(bytes) }
}
