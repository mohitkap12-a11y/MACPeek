import Foundation
import MacPeekCore

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
/// Per-process disk counters (`ri_diskio_bytesread` / `ri_diskio_byteswritten`) from the libproc scan MemoryPeek and
/// CPUPeek also use. libproc refuses other users' processes, which are counted as unreadable instead of being shown.
public struct SystemDiskIOReader: DiskIOReading {
    private let usage: ProcessUsageReading

    public init(usage: ProcessUsageReading = SystemProcessUsageReader()) {
        self.usage = usage
    }

    public func read(isCancelled: @Sendable () -> Bool) throws -> DiskReadResult {
        let snapshot: ProcessUsageSnapshot
        do {
            snapshot = try usage.read(isCancelled: isCancelled)
        } catch let error as ProcessUsageError {
            throw DiskReadError.unavailable(error.localizedDescription)
        }
        return DiskReadResult(counters: snapshot.usages.map {
            DiskCounters(pid: $0.pid, name: $0.name, bytesRead: $0.diskBytesRead, bytesWritten: $0.diskBytesWritten,
                         generation: $0.generation, ageNanoseconds: $0.ageNanoseconds)
        }, unreadable: snapshot.unreadable)
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
