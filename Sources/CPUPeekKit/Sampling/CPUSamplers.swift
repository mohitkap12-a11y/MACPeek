import Foundation
import MacPeekCore

/// Turns cumulative per-core ticks into usage over the interval between two snapshots.
public enum CoreUsage {
    /// Nil when the core count changed (nothing sensible to subtract) or no time passed on any core.
    public static func between(_ old: [CoreTicks], _ new: [CoreTicks]) -> CPUUsage? {
        guard old.count == new.count, !new.isEmpty else { return nil }
        var perCore: [Double] = []
        var userTotal: UInt64 = 0
        var systemTotal: UInt64 = 0
        var allTotal: UInt64 = 0
        for (a, b) in zip(old, new) {
            let user = UInt64(b.user &- a.user) + UInt64(b.nice &- a.nice)
            let system = UInt64(b.system &- a.system)
            let idle = UInt64(b.idle &- a.idle)
            let all = user + system + idle
            perCore.append(all > 0 ? Double(user + system) / Double(all) : 0)
            userTotal += user
            systemTotal += system
            allTotal += all
        }
        guard allTotal > 0 else { return nil }
        let user = Double(userTotal) / Double(allTotal)
        let system = Double(systemTotal) / Double(allTotal)
        return CPUUsage(total: user + system, user: user, system: system, perCore: perCore)
    }
}

/// Turns cumulative per-process CPU time into percent-of-one-core over each interval.
///
/// - The first sample only sets a baseline.
/// - A PID that comes back with a different `generation` is a different process: everything it has used happened
///   inside the interval. A process not seen before likewise started inside the interval.
/// - CPU time that goes down with no generation to explain it is treated as a reused PID and reports nothing.
public struct ProcessCPUSampler: Sendable {
    private struct Seen {
        let generation: UInt64
        let cpuTime: UInt64
    }

    private var previous: [Int: Seen] = [:]
    private var previousDate: Date?
    public private(set) var sampleCount = 0

    public init() {}

    /// True until a second sample has produced a first set of rates.
    public var isBaselineOnly: Bool { sampleCount < 2 }

    public mutating func ingest(_ usages: [ProcessUsage], at date: Date) -> [ProcessCPURow] {
        defer {
            previous = Dictionary(usages.map { ($0.pid, Seen(generation: $0.generation, cpuTime: $0.cpuTimeNanoseconds)) },
                                  uniquingKeysWith: { _, last in last })
            previousDate = date
            sampleCount += 1
        }
        guard let previousDate, date > previousDate else { return [] }
        let intervalNanoseconds = date.timeIntervalSince(previousDate) * 1_000_000_000

        var rows: [ProcessCPURow] = []
        for usage in usages {
            let delta: UInt64
            if let old = previous[usage.pid] {
                if old.generation != usage.generation {
                    delta = usage.cpuTimeNanoseconds
                } else if usage.cpuTimeNanoseconds >= old.cpuTime {
                    delta = usage.cpuTimeNanoseconds - old.cpuTime
                } else {
                    delta = 0
                }
            } else {
                delta = usage.cpuTimeNanoseconds
            }
            guard delta > 0 else { continue }
            rows.append(ProcessCPURow(pid: usage.pid, name: usage.name, percent: Double(delta) / intervalNanoseconds * 100))
        }
        return rows.sorted { ($0.percent, Double($1.pid)) > ($1.percent, Double($0.pid)) }
    }
}

/// Plain-language headline for the CPU screen.
public enum CPUAssessment {
    public static func headline(usage: CPUUsage, top: ProcessCPURow?, thermal: ThermalLevel?) -> String {
        if let thermal, thermal.isElevated {
            return "Your Mac is running hot" + (top.map { ". Busiest: \($0.name)" } ?? "")
        }
        switch usage.total {
        case ..<0.2: return "CPU is mostly idle"
        case ..<0.6: return "CPU is moderately busy" + (top.map { ". Busiest: \($0.name)" } ?? "")
        default: return "CPU is busy" + (top.map { ". Busiest: \($0.name)" } ?? "")
        }
    }

    /// The launcher line: thermal pressure if macOS reports any, otherwise the 1-minute load average.
    public static func launcherSummary(_ snapshot: CPUSnapshot) -> String? {
        if let thermal = snapshot.thermal, thermal.isElevated { return "Running hot" }
        guard let load = snapshot.loadAverage.first else { return nil }
        return String(format: "Load %.1f", load)
    }
}
