import Foundation

/// Cumulative scheduler ticks for one logical CPU since boot (`host_processor_info(PROCESSOR_CPU_LOAD_INFO)`).
/// They are 32-bit and wrap, so differences use wrapping arithmetic.
public struct CoreTicks: Equatable, Sendable {
    public let user: UInt32
    public let system: UInt32
    public let idle: UInt32
    public let nice: UInt32

    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

/// How the CPU is built, as macOS reports it. Read once; it does not change while the Mac runs.
public struct CPUTopology: Equatable, Sendable {
    /// One group per performance level (Apple silicon: performance and efficiency cores), largest level first.
    public struct CoreGroup: Equatable, Sendable {
        public let name: String
        public let logicalCores: Int

        public init(name: String, logicalCores: Int) {
            self.name = name
            self.logicalCores = logicalCores
        }
    }

    /// `machdep.cpu.brand_string`, e.g. "Apple M2".
    public let chip: String?
    public let logicalCores: Int
    public let groups: [CoreGroup]

    public init(chip: String?, logicalCores: Int, groups: [CoreGroup]) {
        self.chip = chip
        self.logicalCores = logicalCores
        self.groups = groups
    }

    /// "4 performance · 4 efficiency" when macOS reports core types, otherwise "8 cores".
    public var coresLabel: String {
        guard groups.count > 1 else { return logicalCores == 1 ? "1 core" : "\(logicalCores) cores" }
        return groups.map { "\($0.logicalCores) \($0.name.lowercased())" }.joined(separator: " · ")
    }
}

/// `ProcessInfo.thermalState`, mirrored so the logic can be tested anywhere.
public enum ThermalLevel: String, Equatable, Sendable {
    case nominal, fair, serious, critical

    public var label: String {
        switch self {
        case .nominal: return "Normal"
        case .fair: return "Slightly raised"
        case .serious: return "High: macOS may slow the CPU to cool down"
        case .critical: return "Critical: macOS is slowing the CPU to cool down"
        }
    }

    public var isElevated: Bool { self == .serious || self == .critical }
}

/// One reading of the whole CPU.
public struct CPUSnapshot: Equatable, Sendable {
    public let cores: [CoreTicks]
    /// 1, 5 and 15 minute load averages.
    public let loadAverage: [Double]
    public let thermal: ThermalLevel?

    public init(cores: [CoreTicks], loadAverage: [Double], thermal: ThermalLevel?) {
        self.cores = cores
        self.loadAverage = loadAverage
        self.thermal = thermal
    }
}

/// CPU use over the last sampling interval. Fractions are 0...1.
public struct CPUUsage: Equatable, Sendable {
    public let total: Double
    public let user: Double
    public let system: Double
    public let perCore: [Double]

    public init(total: Double, user: Double, system: Double, perCore: [Double]) {
        self.total = total
        self.user = user
        self.system = system
        self.perCore = perCore
    }
}

/// One process's CPU use over the last interval. 100 % is one core fully busy, as in Activity Monitor, so a busy
/// multi-threaded process can exceed 100 %.
public struct ProcessCPURow: Identifiable, Equatable, Sendable {
    public var id: Int { pid }
    public let pid: Int
    public let name: String
    public let percent: Double

    public init(pid: Int, name: String, percent: Double) {
        self.pid = pid
        self.name = name
        self.percent = percent
    }
}

public enum CPUReadError: Error, LocalizedError, Equatable {
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let detail): return detail
        }
    }
}

public enum PercentText {
    /// 0.423 → "42 %"; 0.004 → "0 %". Fractions of the whole CPU.
    public static func fraction(_ value: Double) -> String { "\(Int((max(value, 0) * 100).rounded())) %" }

    /// 183.4 → "183 %"; 0.4 → "0.4 %". Percent of one core.
    public static func ofOneCore(_ percent: Double) -> String {
        let tenths = (max(percent, 0) * 10).rounded() / 10
        // Round first, so 9.97 reads "10 %", not "10.0 %".
        return tenths < 10 ? String(format: "%.1f %%", tenths) : "\(Int(tenths.rounded())) %"
    }
}
