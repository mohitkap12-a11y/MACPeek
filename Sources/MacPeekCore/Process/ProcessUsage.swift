import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// What macOS has counted for one process since it started: CPU time and its memory footprint right now.
public struct ProcessUsage: Equatable, Sendable {
    public let pid: Int
    public let name: String
    /// Identifies *which* process holds the PID (its start time as the OS reports it). Zero means unknown.
    public let generation: UInt64
    /// User + system CPU time since the process started, in nanoseconds.
    public let cpuTimeNanoseconds: UInt64
    /// Physical memory footprint in bytes: the figure Activity Monitor's Memory column shows.
    public let memoryFootprintBytes: UInt64

    public init(pid: Int, name: String, generation: UInt64 = 0, cpuTimeNanoseconds: UInt64, memoryFootprintBytes: UInt64) {
        self.pid = pid
        self.name = name
        self.generation = generation
        self.cpuTimeNanoseconds = cpuTimeNanoseconds
        self.memoryFootprintBytes = memoryFootprintBytes
    }
}

public struct ProcessUsageSnapshot: Equatable, Sendable {
    public let usages: [ProcessUsage]
    /// Processes macOS would not report on (other users' and protected processes).
    public let unreadable: Int

    public init(usages: [ProcessUsage], unreadable: Int) {
        self.usages = usages
        self.unreadable = unreadable
    }
}

public enum ProcessUsageError: Error, LocalizedError, Equatable {
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let detail): return detail
        }
    }
}

/// A flag a synchronous scan polls so that cancelling the surrounding task stops a scan that is already running.
public final class ProcessScanCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    public func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}

public protocol ProcessUsageReading: Sendable {
    /// Reads every process the current user may inspect. Synchronous (one call per process), so callers run it off
    /// the main thread; `isCancelled` is polled between processes and a cancelled scan throws `CancellationError`.
    func read(isCancelled: @Sendable () -> Bool) throws -> ProcessUsageSnapshot
}

public extension ProcessUsageReading {
    func read() throws -> ProcessUsageSnapshot { try read(isCancelled: { false }) }
}

#if canImport(Darwin)
/// Per-process counters from `proc_pid_rusage(RUSAGE_INFO_V4)`. libproc refuses other users' processes, which are
/// counted as unreadable instead of being shown.
public struct SystemProcessUsageReader: ProcessUsageReading {
    /// `ri_user_time` / `ri_system_time` are in Mach absolute time units, which are nanoseconds on Intel but not on
    /// Apple silicon. The timebase converts them.
    private let timebaseNumer: UInt64
    private let timebaseDenom: UInt64

    public init() {
        var timebase = mach_timebase_info_data_t()
        if mach_timebase_info(&timebase) == KERN_SUCCESS, timebase.denom != 0 {
            timebaseNumer = UInt64(timebase.numer)
            timebaseDenom = UInt64(timebase.denom)
        } else {
            timebaseNumer = 1
            timebaseDenom = 1
        }
    }

    public func read(isCancelled: @Sendable () -> Bool) throws -> ProcessUsageSnapshot {
        let pids = allPIDs()
        guard !pids.isEmpty else { throw ProcessUsageError.unavailable("macOS did not list any processes.") }
        var usages: [ProcessUsage] = []
        var unreadable = 0
        for pid in pids where pid > 0 {
            if isCancelled() { throw CancellationError() }
            guard let usage = rusage(pid) else {
                unreadable += 1
                continue
            }
            let ticks = usage.ri_user_time &+ usage.ri_system_time
            let nanoseconds = ticks.multipliedReportingOverflow(by: timebaseNumer)
            let cpu = nanoseconds.overflow ? UInt64.max : nanoseconds.partialValue / timebaseDenom
            usages.append(ProcessUsage(pid: Int(pid), name: name(of: pid), generation: usage.ri_proc_start_abstime,
                                       cpuTimeNanoseconds: cpu, memoryFootprintBytes: usage.ri_phys_footprint))
        }
        return ProcessUsageSnapshot(usages: usages, unreadable: unreadable)
    }

    private func allPIDs() -> [pid_t] {
        var capacity = 2048
        while capacity <= 1 << 20 {
            var pids = [pid_t](repeating: 0, count: capacity)
            let count = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.stride)))
            if count < 0 { return [] }
            if count < capacity { return Array(pids.prefix(count)) }
            capacity *= 2
        }
        return []
    }

    private func rusage(_ pid: pid_t) -> rusage_info_v4? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        return result == 0 ? info : nil
    }

    private func name(of pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(cString: buffer) : "PID \(pid)"
    }
}
#else
/// MacPeek ships for macOS only; on Linux the reader reports itself unavailable so tests can skip.
public struct SystemProcessUsageReader: ProcessUsageReading {
    public init() {}

    public func read(isCancelled: @Sendable () -> Bool) throws -> ProcessUsageSnapshot {
        throw ProcessUsageError.unavailable("Per-process usage is read with libproc, which exists only on macOS.")
    }
}
#endif
