import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public protocol CPUReading: Sendable {
    /// Per-core ticks, load average and thermal state. One Mach call and two cheap reads.
    func snapshot() throws -> CPUSnapshot
    /// Chip name and core layout. Read once.
    func topology() -> CPUTopology
}

#if canImport(Darwin)
/// `host_processor_info(PROCESSOR_CPU_LOAD_INFO)`, `getloadavg`, `ProcessInfo.thermalState` and the `hw.*` /
/// `machdep.cpu.brand_string` sysctls. None of them needs a permission.
public struct SystemCPUReader: CPUReading {
    public init() {}

    public func snapshot() throws -> CPUSnapshot {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else {
            throw CPUReadError.unavailable("macOS did not report CPU load (error \(result)).")
        }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        let stride = Int(CPU_STATE_MAX)
        var cores: [CoreTicks] = []
        for index in 0..<Int(cpuCount) {
            let base = index * stride
            guard base + stride <= Int(infoCount) else { break }
            cores.append(CoreTicks(user: UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                                   system: UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                                   idle: UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                                   nice: UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])))
        }
        return CPUSnapshot(cores: cores, loadAverage: Self.loadAverage(), thermal: Self.thermal())
    }

    public func topology() -> CPUTopology {
        let logical: Int32 = Self.sysctlValue("hw.logicalcpu") ?? Int32(ProcessInfo.processInfo.activeProcessorCount)
        var groups: [CPUTopology.CoreGroup] = []
        let levels: Int32 = Self.sysctlValue("hw.nperflevels") ?? 0
        if levels > 1 {
            for level in 0..<Int(levels) {
                guard let cores: Int32 = Self.sysctlValue("hw.perflevel\(level).logicalcpu"), cores > 0 else { continue }
                let name = Self.sysctlString("hw.perflevel\(level).name") ?? "Level \(level)"
                groups.append(.init(name: name, logicalCores: Int(cores)))
            }
        }
        return CPUTopology(chip: Self.sysctlString("machdep.cpu.brand_string"), logicalCores: Int(logical), groups: groups)
    }

    private static func thermal() -> ThermalLevel? {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return nil
        }
    }

    private static func sysctlValue<T: FixedWidthInteger>(_ name: String) -> T? {
        var value: T = 0
        var size = MemoryLayout<T>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0, size == MemoryLayout<T>.size else { return nil }
        return value
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let text = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
#else
/// Linux reader (`/proc/stat`) so the sampler can be exercised in CI. MacPeek itself ships for macOS.
public struct SystemCPUReader: CPUReading {
    public init() {}

    public func snapshot() throws -> CPUSnapshot {
        guard let stat = try? String(contentsOfFile: "/proc/stat", encoding: .utf8) else {
            throw CPUReadError.unavailable("/proc/stat is not available.")
        }
        var cores: [CoreTicks] = []
        for line in stat.split(separator: "\n") where line.hasPrefix("cpu") && !line.hasPrefix("cpu ") {
            let fields = line.split(separator: " ").dropFirst().compactMap { UInt64($0) }
            guard fields.count >= 4 else { continue }
            cores.append(CoreTicks(user: UInt32(truncatingIfNeeded: fields[0]), system: UInt32(truncatingIfNeeded: fields[2]),
                                   idle: UInt32(truncatingIfNeeded: fields[3]), nice: UInt32(truncatingIfNeeded: fields[1])))
        }
        guard !cores.isEmpty else { throw CPUReadError.unavailable("/proc/stat listed no CPUs.") }
        return CPUSnapshot(cores: cores, loadAverage: Self.loadAverage(), thermal: nil)
    }

    public func topology() -> CPUTopology {
        CPUTopology(chip: nil, logicalCores: ProcessInfo.processInfo.activeProcessorCount, groups: [])
    }
}
#endif

extension SystemCPUReader {
    static func loadAverage() -> [Double] {
        var values = [Double](repeating: 0, count: 3)
        let count = getloadavg(&values, 3)
        return count > 0 ? Array(values.prefix(Int(count))) : []
    }
}
