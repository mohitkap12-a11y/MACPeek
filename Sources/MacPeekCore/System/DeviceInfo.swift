import Foundation
#if canImport(Darwin)
import Darwin
#endif
#if canImport(SystemConfiguration)
import SystemConfiguration
#endif

/// Who this Mac is: the names people know it by, its model and how long it has been up. Read once; only the uptime
/// changes while the Mac runs, and it is derived from the boot time.
public struct DeviceInfo: Equatable, Codable, Sendable {
    /// The name in System Settings › General › Sharing, e.g. "Design Studio 01".
    public let computerName: String?
    /// The Bonjour name, without ".local", e.g. "Design-Studio-01".
    public let localHostName: String?
    /// `hw.model`, e.g. "Mac16,7".
    public let modelIdentifier: String?
    /// "26.1", or "26.1.2" when there is a patch version.
    public let macOSVersion: String
    public let bootTime: Date?

    public init(computerName: String?, localHostName: String?, modelIdentifier: String?, macOSVersion: String, bootTime: Date?) {
        self.computerName = computerName
        self.localHostName = localHostName
        self.modelIdentifier = modelIdentifier
        self.macOSVersion = macOSVersion
        self.bootTime = bootTime
    }

    /// The computer name, else the Bonjour name, else "This Mac".
    public var displayName: String { computerName ?? localHostName ?? "This Mac" }

    /// Seconds since boot, or nil when the boot time is unknown. Never negative, even if the clock moved backwards.
    public func uptime(at now: Date = Date()) -> TimeInterval? {
        bootTime.map { max(now.timeIntervalSince($0), 0) }
    }

    /// 26, 1, 0 → "26.1"; 26, 1, 2 → "26.1.2".
    public static func versionLabel(major: Int, minor: Int, patch: Int) -> String {
        patch == 0 ? "\(major).\(minor)" : "\(major).\(minor).\(patch)"
    }
}

public enum UptimeText {
    /// 533_000 → "6d 4h"; 33_120 → "9h 12m"; 720 → "12m"; 20 → "<1m".
    public static func label(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0))
        let days = total / 86_400, hours = total % 86_400 / 3_600, minutes = total % 3_600 / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return minutes > 0 ? "\(minutes)m" : "<1m"
    }
}

public protocol DeviceInfoReading: Sendable {
    /// A few sysctl and SystemConfiguration calls, no permission needed. Anything macOS does not report is nil.
    func read() -> DeviceInfo
}

/// Reads the names with SystemConfiguration, `hw.model`, `kern.boottime` and the macOS version from `ProcessInfo`.
/// On Linux (CI only) the boot time comes from `/proc/stat` and the names and model are not reported.
public struct SystemDeviceInfoReader: DeviceInfoReading {
    public init() {}

    public func read() -> DeviceInfo {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return DeviceInfo(computerName: Self.computerName(), localHostName: Self.localHostName(),
                          modelIdentifier: Self.modelIdentifier(),
                          macOSVersion: DeviceInfo.versionLabel(major: version.majorVersion, minor: version.minorVersion,
                                                                patch: version.patchVersion),
                          bootTime: Self.bootTime())
    }

    private static func computerName() -> String? {
        #if canImport(SystemConfiguration)
        return nonEmpty(SCDynamicStoreCopyComputerName(nil, nil) as String?)
        #else
        return nil
        #endif
    }

    private static func localHostName() -> String? {
        #if canImport(SystemConfiguration)
        return nonEmpty(SCDynamicStoreCopyLocalHostName(nil) as String?)
        #else
        return nil
        #endif
    }

    private static func modelIdentifier() -> String? {
        #if canImport(Darwin)
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return nil }
        return nonEmpty(String(cString: buffer))
        #else
        return nil
        #endif
    }

    private static func bootTime() -> Date? {
        #if canImport(Darwin)
        var value = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &value, &size, nil, 0) == 0, value.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(value.tv_sec) + TimeInterval(value.tv_usec) / 1_000_000)
        #else
        guard let stat = try? String(contentsOfFile: "/proc/stat", encoding: .utf8),
              let line = stat.split(separator: "\n").first(where: { $0.hasPrefix("btime ") }),
              let seconds = TimeInterval(line.dropFirst("btime ".count).trimmingCharacters(in: .whitespaces)) else { return nil }
        return Date(timeIntervalSince1970: seconds)
        #endif
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
