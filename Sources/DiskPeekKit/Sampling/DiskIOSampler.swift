import Foundation

/// Turns cumulative per-process counters into per-interval rates.
///
/// - The first sample only sets a baseline (there is nothing to subtract yet).
/// - A PID that comes back with a different `generation` (process start time) is a different process and starts
///   a new baseline. Without a generation, a counter that goes *down* means the same; nothing negative or absurd
///   is ever reported.
/// - A process that was not in the previous sample started inside the interval, so everything it has done so
///   far happened inside it, and its whole counter counts as that interval's activity.
public struct DiskIOSampler: Sendable {
    private struct Total {
        var read: UInt64 = 0
        var written: UInt64 = 0
    }

    private var previous: [Int: DiskCounters] = [:]
    private var previousDate: Date?
    private var totals: [Int: Total] = [:]
    public private(set) var sampleCount = 0

    public init() {}

    /// True until a second sample has produced a first set of rates.
    public var isBaselineOnly: Bool { sampleCount < 2 }

    public mutating func ingest(_ counters: [DiskCounters], at date: Date) -> [DiskActivity] {
        defer {
            previous = Dictionary(counters.map { ($0.pid, $0) }, uniquingKeysWith: { _, last in last })
            previousDate = date
            totals = totals.filter { previous[$0.key] != nil }
            sampleCount += 1
        }
        guard let previousDate, date > previousDate else {
            // Baseline: remember where every counter stands.
            for counter in counters where totals[counter.pid] == nil { totals[counter.pid] = Total() }
            return []
        }
        let interval = date.timeIntervalSince(previousDate)

        var result: [DiskActivity] = []
        for counter in counters {
            let readDelta: UInt64
            let writeDelta: UInt64
            if let old = previous[counter.pid] {
                if old.generation != counter.generation {
                    // A different process now holds this PID (it started inside the interval), whatever its counters.
                    totals[counter.pid] = Total()
                    readDelta = counter.bytesRead
                    writeDelta = counter.bytesWritten
                } else if counter.bytesRead >= old.bytesRead && counter.bytesWritten >= old.bytesWritten {
                    readDelta = counter.bytesRead - old.bytesRead
                    writeDelta = counter.bytesWritten - old.bytesWritten
                } else {
                    // Counters went down with no generation to tell us why: treat it as a reused PID and start over.
                    totals[counter.pid] = Total()
                    readDelta = 0
                    writeDelta = 0
                }
            } else {
                readDelta = counter.bytesRead
                writeDelta = counter.bytesWritten
            }
            var total = totals[counter.pid] ?? Total()
            total.read &+= readDelta
            total.written &+= writeDelta
            totals[counter.pid] = total

            if readDelta > 0 || writeDelta > 0 || total.read > 0 || total.written > 0 {
                result.append(DiskActivity(
                    pid: counter.pid, name: counter.name,
                    readBytesPerSecond: Double(readDelta) / interval,
                    writeBytesPerSecond: Double(writeDelta) / interval,
                    readSinceOpened: total.read, writtenSinceOpened: total.written))
            }
        }
        return result
    }

    public static func sorted(_ activity: [DiskActivity], by sort: DiskSort) -> [DiskActivity] {
        switch sort {
        case .rate:
            return activity.sorted { ($0.totalBytesPerSecond, Double($1.pid)) > ($1.totalBytesPerSecond, Double($0.pid)) }
        case .total:
            return activity.sorted { ($0.totalSinceOpened, UInt64($1.pid)) > ($1.totalSinceOpened, UInt64($0.pid)) }
        }
    }
}
