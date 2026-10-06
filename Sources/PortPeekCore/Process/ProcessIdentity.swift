import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Low-level process operations behind a protocol so `KillService` is testable
/// (PID reuse, vanishing processes, EPERM) without touching real processes.
public protocol ProcessInspecting: Sendable {
    func isAlive(pid: Int) -> Bool
    /// Process start time in seconds since epoch; together with the PID it identifies a process.
    func startTime(pid: Int) -> TimeInterval?
    /// Returns 0 on success or the errno value.
    func signal(pid: Int, signal: Int32) -> Int32
}

public struct SystemProcessInspector: ProcessInspecting {
    public init() {}

    public func signal(pid: Int, signal: Int32) -> Int32 {
        kill(pid_t(pid), signal) == 0 ? 0 : errno
    }

    #if canImport(Darwin)
    public func isAlive(pid: Int) -> Bool {
        guard let info = kinfo(pid) else { return false }
        return info.kp_proc.p_stat != 5 // 5 == SZOMB: exited but not yet reaped
    }

    public func startTime(pid: Int) -> TimeInterval? {
        guard let info = kinfo(pid) else { return nil }
        let tv = info.kp_proc.p_un.__p_starttime
        return TimeInterval(tv.tv_sec) + TimeInterval(tv.tv_usec) / 1_000_000
    }

    private func kinfo(_ pid: Int) -> kinfo_proc? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, Int32(pid)]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info
    }
    #else
    // Linux fallback so the core can be unit-tested in CI. PortPeek itself ships for macOS.
    public func isAlive(pid: Int) -> Bool {
        guard let stat = try? String(contentsOfFile: "/proc/\(pid)/stat", encoding: .utf8),
              let close = stat.lastIndex(of: ")") else { return false }
        let fields = stat[stat.index(after: close)...].split(separator: " ")
        return fields.first != "Z"
    }

    public func startTime(pid: Int) -> TimeInterval? {
        guard let stat = try? String(contentsOfFile: "/proc/\(pid)/stat", encoding: .utf8),
              let close = stat.lastIndex(of: ")") else { return nil }
        let fields = stat[stat.index(after: close)...].split(separator: " ")
        guard fields.count > 19, let ticks = Double(fields[19]) else { return nil }
        return ticks / 100 // clock ticks since boot; only compared against itself
    }
    #endif
}
