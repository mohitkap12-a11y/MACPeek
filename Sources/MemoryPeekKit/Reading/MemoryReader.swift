import Foundation
#if canImport(Darwin)
import Darwin
#endif

public protocol MemoryReading: Sendable {
    /// System-wide memory statistics. A handful of sysctl and Mach calls: cheap enough for the launcher summary.
    func read() throws -> MemoryStats
}

#if canImport(Darwin)
/// Reads `hw.memsize`, `host_statistics64(HOST_VM_INFO64)`, `vm.swapusage` and `kern.memorystatus_vm_pressure_level`.
/// None of them needs a permission. Swap and pressure are optional: if macOS refuses
/// one, it is shown as not reported instead of failing the whole read.
public struct SystemMemoryReader: MemoryReading {
    public init() {}

    public func read() throws -> MemoryStats {
        guard let physical: UInt64 = Self.sysctlValue("hw.memsize"), physical > 0 else {
            throw MemoryReadError.unavailable("macOS did not report the amount of memory.")
        }
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result = withUnsafeMutablePointer(to: &vm) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            throw MemoryReadError.unavailable("macOS did not report memory statistics (error \(result)).")
        }

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        let hasSwap = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0
        let level: Int32? = Self.sysctlValue("kern.memorystatus_vm_pressure_level")

        return MemoryStats(
            physicalBytes: physical, pageSize: UInt64(vm_kernel_page_size),
            wiredPages: UInt64(vm.wire_count), compressorPages: UInt64(vm.compressor_page_count),
            purgeablePages: UInt64(vm.purgeable_count), externalPages: UInt64(vm.external_page_count),
            internalPages: UInt64(vm.internal_page_count),
            swapUsedBytes: hasSwap ? swap.xsu_used : nil,
            pressure: level.flatMap(MemoryPressure.init(sysctlLevel:)),
            swapTotalBytes: hasSwap ? swap.xsu_total : nil)
    }

    private static func sysctlValue<T: FixedWidthInteger>(_ name: String) -> T? {
        var value: T = 0
        var size = MemoryLayout<T>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0, size == MemoryLayout<T>.size else { return nil }
        return value
    }
}
#else
/// MacPeek ships for macOS only; on Linux the reader reports itself unavailable so tests can skip.
public struct SystemMemoryReader: MemoryReading {
    public init() {}

    public func read() throws -> MemoryStats {
        throw MemoryReadError.unavailable("Memory statistics are read with Mach calls, which exist only on macOS.")
    }
}
#endif
