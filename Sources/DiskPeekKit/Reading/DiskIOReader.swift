import Foundation
#if canImport(Darwin)
import Darwin
#endif

public protocol DiskIOReading: Sendable {
    /// Reads the counters of every process the current user may inspect. Synchronous (one call per process), so
    /// callers run it off the main thread and pass `isCancelled`, which is polled between processes: a cancelled
    /// scan throws `CancellationError` promptly instead of running to the end.
    func read(isCancelled: @Sendable () -> Bool) throws -> DiskReadResult
}

public extension DiskIOReading {
    func read() throws -> DiskReadResult { try read(isCancelled: { false }) }
}

public enum DiskReadError: Error, LocalizedError, Equatable {
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let detail): return detail
        }
    }
}

#if canImport(Darwin)
/// Per-process disk counters from `proc_pid_rusage(RUSAGE_INFO_V4)` (`ri_diskio_bytesread` / `ri_diskio_byteswritten`).
/// libproc refuses other users' processes, which are counted as unreadable instead of being shown.
public struct SystemDiskIOReader: DiskIOReading {
    public init() {}

    public func read(isCancelled: @Sendable () -> Bool) throws -> DiskReadResult {
        let pids = allPIDs()
        guard !pids.isEmpty else { throw DiskReadError.unavailable("macOS did not list any processes.") }
        var counters: [DiskCounters] = []
        var unreadable = 0
        for pid in pids where pid > 0 {
            if isCancelled() { throw CancellationError() }
            guard let usage = rusage(pid) else {
                unreadable += 1
                continue
            }
            counters.append(DiskCounters(pid: Int(pid), name: name(of: pid),
                                         bytesRead: usage.ri_diskio_bytesread, bytesWritten: usage.ri_diskio_byteswritten,
                                         generation: usage.ri_proc_start_abstime))
        }
        return DiskReadResult(counters: counters, unreadable: unreadable)
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
/// Linux fallback (`/proc/<pid>/io`) so the sampler and reader can be tested in CI. MacPeek itself ships for macOS.
public struct SystemDiskIOReader: DiskIOReading {
    public init() {}

    public func read(isCancelled: @Sendable () -> Bool) throws -> DiskReadResult {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: "/proc") else {
            throw DiskReadError.unavailable("/proc is not available.")
        }
        var counters: [DiskCounters] = []
        var unreadable = 0
        for entry in entries {
            guard let pid = Int(entry) else { continue }
            if isCancelled() { throw CancellationError() }
            guard let io = try? String(contentsOfFile: "/proc/\(pid)/io", encoding: .utf8) else {
                unreadable += 1
                continue
            }
            var read: UInt64?
            var written: UInt64?
            for line in io.split(separator: "\n") {
                if line.hasPrefix("read_bytes:") { read = UInt64(line.dropFirst("read_bytes:".count).trimmingCharacters(in: .whitespaces)) }
                if line.hasPrefix("write_bytes:") { written = UInt64(line.dropFirst("write_bytes:".count).trimmingCharacters(in: .whitespaces)) }
            }
            guard let read, let written else {
                unreadable += 1
                continue
            }
            let comm = (try? String(contentsOfFile: "/proc/\(pid)/comm", encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "PID \(pid)"
            counters.append(DiskCounters(pid: pid, name: comm, bytesRead: read, bytesWritten: written,
                                         generation: startTicks(pid: pid)))
        }
        return DiskReadResult(counters: counters, unreadable: unreadable)
    }

    /// Field 22 of `/proc/<pid>/stat` (start time in clock ticks since boot): unique per process lifetime.
    private func startTicks(pid: Int) -> UInt64 {
        guard let stat = try? String(contentsOfFile: "/proc/\(pid)/stat", encoding: .utf8), let close = stat.lastIndex(of: ")") else { return 0 }
        let fields = stat[stat.index(after: close)...].split(separator: " ")
        return fields.count > 19 ? (UInt64(fields[19]) ?? 0) : 0
    }
}
#endif
