import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// The running OS version from `ProcessInfo` and the build from `sysctl kern.osversion`. No subprocess.
public struct SystemOperatingSystem: OperatingSystemProviding {
    public init() {}

    public func current() -> OperatingSystemInfo {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return OperatingSystemInfo(major: version.majorVersion, minor: version.minorVersion, patch: version.patchVersion,
                                   build: Self.build())
    }

    static func build() -> String? {
        #if canImport(Darwin)
        var size = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.osversion", &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
        #else
        return nil
        #endif
    }
}
