import Foundation
#if canImport(Darwin)
import Darwin
#endif

public protocol ProcessEnvironmentReading: Sendable {
    func read(pid: Int) throws -> ProcessArguments
}

public enum MacPeekEnvironment {
    /// MacPeek's own environment, sorted by name.
    public static func variables(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> [EnvVariable] {
        environment.map { EnvVariable(name: $0.key, value: $0.value) }.sorted { $0.name < $1.name }
    }
}

#if canImport(Darwin)
/// Reads another process's arguments and environment with `sysctl(KERN_PROCARGS2)`. macOS only returns this for
/// processes owned by the current user, and not for system-protected binaries; both come back as errors that
/// are reported honestly instead of an empty environment.
public struct SystemProcessEnvironmentReader: ProcessEnvironmentReading {
    public init() {}

    public func read(pid: Int) throws -> ProcessArguments {
        // A PID is a 32-bit value: anything outside that range cannot be a process, and must not trap in Int32(_:).
        guard pid > 0, pid <= Int(Int32.max) else { throw EnvError.noSuchProcess }
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, Int32(pid)]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else { throw map(errno) }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &size, nil, 0) == 0 else { throw map(errno) }
        guard let parsed = ProcArgsParser.parse(Array(buffer.prefix(size))) else {
            throw EnvError.unavailable("macOS returned process data in an unexpected format.")
        }
        return parsed
    }

    private func map(_ code: Int32) -> EnvError {
        switch code {
        case ESRCH: return .noSuchProcess
        case EPERM, EACCES: return .notPermitted
        // macOS answers EINVAL for system-protected processes whose environment it hides.
        case EINVAL: return .unavailable("macOS hides the environment of this process (it is protected, or it is not running).")
        default: return .unavailable("macOS could not read this process (error \(code)).")
        }
    }
}
#else
/// Linux fallback (`/proc/<pid>/cmdline` and `environ`) so the reader can be tested in CI.
public struct SystemProcessEnvironmentReader: ProcessEnvironmentReading {
    public init() {}

    public func read(pid: Int) throws -> ProcessArguments {
        guard pid > 0, pid <= Int(Int32.max) else { throw EnvError.noSuchProcess }
        guard FileManager.default.fileExists(atPath: "/proc/\(pid)") else { throw EnvError.noSuchProcess }
        guard let environ = FileManager.default.contents(atPath: "/proc/\(pid)/environ") else { throw EnvError.notPermitted }
        let cmdline = FileManager.default.contents(atPath: "/proc/\(pid)/cmdline") ?? Data()
        let arguments = String(decoding: cmdline, as: UTF8.self).split(separator: "\0").map(String.init)
        let variables = String(decoding: environ, as: UTF8.self).split(separator: "\0").compactMap { entry -> EnvVariable? in
            guard let equals = entry.firstIndex(of: "=") else { return nil }
            return EnvVariable(name: String(entry[entry.startIndex..<equals]), value: String(entry[entry.index(after: equals)...]))
        }
        return ProcessArguments(executable: arguments.first, arguments: arguments, environment: variables)
    }
}
#endif
