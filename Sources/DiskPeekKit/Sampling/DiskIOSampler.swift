import Foundation
import MacPeekCore

/// Turns cumulative per-process disk counters into per-interval rates and totals since DiskPeek opened. The baseline,
/// reused-PID and new-process rules are `ProcessCounterSampler`'s, shared with CPUPeek.
public struct DiskIOSampler: Sendable {
    private struct Total {
        var read: UInt64 = 0
        var written: UInt64 = 0
    }

    private var counters = ProcessCounterSampler()
    private var totals: [Int: Total] = [:]

    public init() {}

    public var sampleCount: Int { counters.sampleCount }

    /// True until a second sample has produced a first set of rates.
    public var isBaselineOnly: Bool { counters.isBaselineOnly }

    public mutating func ingest(_ samples: [DiskCounters], at date: Date) -> [DiskActivity] {
        let interval = counters.ingest(samples.map {
            ProcessCounterSampler.Sample(pid: $0.pid, generation: $0.generation, ageNanoseconds: $0.ageNanoseconds,
                                         counters: [$0.bytesRead, $0.bytesWritten])
        }, at: date)
        let present = Set(samples.map(\.pid))
        totals = totals.filter { present.contains($0.key) }
        guard let interval else { return [] }

        var result: [DiskActivity] = []
        for sample in samples {
            var total = totals[sample.pid] ?? Total()
            let delta = interval.deltas[sample.pid] ?? .rebaselined
            switch delta {
            case .continued: break
            case .started, .rebaselined: total = Total()
            }
            let values = delta.values ?? [0, 0]
            total.read &+= values[0]
            total.written &+= values[1]
            totals[sample.pid] = total

            if values[0] > 0 || values[1] > 0 || total.read > 0 || total.written > 0 {
                result.append(DiskActivity(
                    pid: sample.pid, name: sample.name,
                    readBytesPerSecond: Double(values[0]) / interval.seconds,
                    writeBytesPerSecond: Double(values[1]) / interval.seconds,
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
