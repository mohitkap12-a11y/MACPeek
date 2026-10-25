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

/// Turns cumulative per-process CPU time into percent-of-one-core over each interval. The baseline, reused-PID and
/// new-process rules are `ProcessCounterSampler`'s, shared with DiskPeek: in particular a long-running process that
/// could not be read last time starts a new baseline instead of having its whole lifetime charged to one interval.
public struct ProcessCPUSampler: Sendable {
    private var counters = ProcessCounterSampler()

    public init() {}

    /// True until a second sample has produced a first set of rates.
    public var isBaselineOnly: Bool { counters.isBaselineOnly }

    public mutating func ingest(_ usages: [ProcessUsage], at date: Date) -> [ProcessCPURow] {
        let samples = usages.map {
            ProcessCounterSampler.Sample(pid: $0.pid, generation: $0.generation, ageNanoseconds: $0.ageNanoseconds,
                                         counters: [$0.cpuTimeNanoseconds])
        }
        guard let interval = counters.ingest(samples, at: date) else { return [] }
        let intervalNanoseconds = interval.seconds * 1_000_000_000
        var rows: [ProcessCPURow] = []
        for usage in usages {
            guard let delta = interval.deltas[usage.pid]?.values?.first, delta > 0 else { continue }
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

    /// The launcher ring: overall use, with the 1-minute load average under it, or "running hot" when macOS reports a
    /// high thermal state.
    public static func gaugeReading(usage: CPUUsage, snapshot: CPUSnapshot) -> GaugeReading {
        let hot = snapshot.thermal?.isElevated == true
        let caption = hot ? "running hot" : (snapshot.loadAverage.first.map { String(format: "load %.2f", $0) } ?? "")
        return GaugeReading(fraction: usage.total, caption: caption, isAlert: hot)
    }
}
