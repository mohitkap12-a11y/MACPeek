import Foundation

/// Turns cumulative per-process counters into per-interval differences, with the rules every MacPeek sampler shares:
///
/// - The first sample only sets a baseline (there is nothing to subtract yet).
/// - Same process (same PID and `generation`), counters not lower: the difference is that interval's activity.
/// - A PID that comes back with a different `generation` is a different process that started inside the interval,
///   so everything it has done so far counts toward it.
/// - A PID that was not in the previous sample counts the same way **only if its age shows it started inside the
///   interval**. Otherwise it is a long-running process that could not be read last time, and charging its lifetime to
///   one interval would report something absurd, so it starts a new baseline instead.
/// - Counters that go down with no generation to explain them also start a new baseline. Nothing negative or absurd
///   is ever reported.
public struct ProcessCounterSampler: Sendable {
    public struct Sample: Equatable, Sendable {
        public let pid: Int
        public let generation: UInt64
        public let ageNanoseconds: UInt64?
        public let counters: [UInt64]

        public init(pid: Int, generation: UInt64, ageNanoseconds: UInt64?, counters: [UInt64]) {
            self.pid = pid
            self.generation = generation
            self.ageNanoseconds = ageNanoseconds
            self.counters = counters
        }
    }

    public enum Delta: Equatable, Sendable {
        /// The same process as last time; the counters' growth over the interval.
        case continued([UInt64])
        /// A process that started inside the interval; all of its counters.
        case started([UInt64])
        /// Cannot be compared with the previous sample; nothing is reported and it becomes the new baseline.
        case rebaselined

        /// The activity to report for the interval, or nil for `.rebaselined`.
        public var values: [UInt64]? {
            switch self {
            case .continued(let values), .started(let values): return values
            case .rebaselined: return nil
            }
        }
    }

    public struct Interval: Equatable, Sendable {
        public let seconds: TimeInterval
        public let deltas: [Int: Delta]
    }

    private struct Seen {
        let generation: UInt64
        let counters: [UInt64]
    }

    private var previous: [Int: Seen] = [:]
    private var previousDate: Date?
    public private(set) var sampleCount = 0

    public init() {}

    /// True until a second sample has produced a first set of differences.
    public var isBaselineOnly: Bool { sampleCount < 2 }

    /// Nil for the first sample, or when no time passed since the previous one.
    public mutating func ingest(_ samples: [Sample], at date: Date) -> Interval? {
        defer {
            previous = Dictionary(samples.map { ($0.pid, Seen(generation: $0.generation, counters: $0.counters)) },
                                  uniquingKeysWith: { _, last in last })
            previousDate = date
            sampleCount += 1
        }
        guard let previousDate, date > previousDate else { return nil }
        let seconds = date.timeIntervalSince(previousDate)

        var deltas: [Int: Delta] = [:]
        for sample in samples {
            if let old = previous[sample.pid], old.counters.count == sample.counters.count {
                if old.generation != sample.generation {
                    deltas[sample.pid] = .started(sample.counters)
                } else if zip(sample.counters, old.counters).allSatisfy({ $0 >= $1 }) {
                    deltas[sample.pid] = .continued(zip(sample.counters, old.counters).map { $0 - $1 })
                } else {
                    deltas[sample.pid] = .rebaselined
                }
            } else if let age = sample.ageNanoseconds, Double(age) <= seconds * 1_000_000_000 {
                deltas[sample.pid] = .started(sample.counters)
            } else {
                deltas[sample.pid] = .rebaselined
            }
        }
        return Interval(seconds: seconds, deltas: deltas)
    }
}
