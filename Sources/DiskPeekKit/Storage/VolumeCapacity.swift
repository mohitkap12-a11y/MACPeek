import Foundation
import MacPeekCore

/// How full one mounted drive is, as macOS reports it.
public struct VolumeCapacity: Identifiable, Equatable, Codable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let totalBytes: Int64
    /// Space free right now (`volumeAvailableCapacity`).
    public let strictlyFreeBytes: Int64
    /// Space available for things the user saves (`volumeAvailableCapacityForImportantUsage`): free space plus
    /// purgeable space macOS clears on demand. This is the "available" figure Finder shows. Nil when not reported.
    public let availableForImportantUsageBytes: Int64?
    public let isRoot: Bool
    public let isInternal: Bool?
    public let isRemovable: Bool?

    public init(name: String, path: String, totalBytes: Int64, strictlyFreeBytes: Int64,
                availableForImportantUsageBytes: Int64?, isRoot: Bool, isInternal: Bool?, isRemovable: Bool?) {
        self.name = name
        self.path = path
        self.totalBytes = totalBytes
        self.strictlyFreeBytes = strictlyFreeBytes
        self.availableForImportantUsageBytes = availableForImportantUsageBytes
        self.isRoot = isRoot
        self.isInternal = isInternal
        self.isRemovable = isRemovable
    }

    /// What Finder calls available.
    public var availableBytes: Int64 { min(max(availableForImportantUsageBytes ?? strictlyFreeBytes, strictlyFreeBytes), totalBytes) }
    /// Space macOS can free by itself (caches, local snapshots, iCloud copies) when something needs it.
    public var purgeableBytes: Int64 { max(availableBytes - strictlyFreeBytes, 0) }
    public var usedBytes: Int64 { max(totalBytes - availableBytes, 0) }
    public var usedFraction: Double { totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0 }
    /// Under 10 % available. An indication, not a rule macOS applies.
    public var isLowOnSpace: Bool { totalBytes > 0 && Double(availableBytes) < Double(totalBytes) * 0.1 }

    /// The launcher ring: how full the drive is, with what is available under it.
    public var gaugeReading: GaugeReading {
        GaugeReading(fraction: usedFraction, caption: "\(ByteCountText.storage(availableBytes)) free", isAlert: isLowOnSpace)
    }

    public var kindLabel: String? {
        if isRoot { return "Startup disk" }
        if isRemovable == true { return "Removable" }
        if isInternal == false { return "External" }
        return nil
    }

    /// The startup disk first, then internal drives, then the rest by name.
    public static func ordered(_ volumes: [VolumeCapacity]) -> [VolumeCapacity] {
        volumes.sorted { a, b in
            if a.isRoot != b.isRoot { return a.isRoot }
            let ai = a.isInternal ?? false, bi = b.isInternal ?? false
            if ai != bi { return ai }
            return a.name.lowercased() < b.name.lowercased()
        }
    }
}

public protocol VolumeCapacityReading: Sendable {
    /// Local, visible, writable mounted volumes (plus the startup disk).
    func read() throws -> [VolumeCapacity]
}

#if canImport(Darwin)
/// Lists mounts with `getfsstat(MNT_NOWAIT)`, which returns the kernel's cached statistics without touching any file
/// system, so a hung network server or a sleeping external disk cannot stall DiskPeek or be woken by it. Only local,
/// browsable mounts are kept, and read-only ones (mounted disk images, installers) are skipped, except the startup
/// disk, whose sealed system volume is always read-only. Name, internal/removable and the "important usage" figure
/// come from Foundation for the kept volumes only.
public struct SystemVolumeCapacityReader: VolumeCapacityReading {
    public init() {}

    public func read() throws -> [VolumeCapacity] {
        let mounts = try Self.mounts()
        var volumes: [VolumeCapacity] = []
        for mount in mounts {
            let flags = Int32(bitPattern: mount.f_flags)
            let path = Self.string(mount.f_mntonname)
            let isRoot = path == "/"
            guard flags & MNT_LOCAL != 0, flags & MNT_DONTBROWSE == 0, isRoot || flags & MNT_RDONLY == 0 else { continue }
            let blockSize = Int64(mount.f_bsize)
            let total = Int64(clamping: mount.f_blocks) * blockSize
            guard total > 0 else { continue }
            let free = Int64(clamping: mount.f_bavail) * blockSize
            let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeAvailableCapacityForImportantUsageKey,
                                             .volumeIsInternalKey, .volumeIsRemovableKey]
            let values = try? URL(fileURLWithPath: path, isDirectory: true).resourceValues(forKeys: keys)
            volumes.append(VolumeCapacity(
                name: values?.volumeName ?? (isRoot ? "Startup disk" : (path as NSString).lastPathComponent),
                path: path, totalBytes: total, strictlyFreeBytes: free,
                availableForImportantUsageBytes: values?.volumeAvailableCapacityForImportantUsage,
                isRoot: isRoot, isInternal: values?.volumeIsInternal, isRemovable: values?.volumeIsRemovable))
        }
        return VolumeCapacity.ordered(volumes)
    }

    private static func mounts() throws -> [statfs] {
        let count = getfsstat(nil, 0, MNT_NOWAIT)
        guard count > 0 else { throw DiskReadError.unavailable("macOS did not list any mounted drives.") }
        // Room for a mount or two appearing between the two calls.
        var buffer = Array(repeating: statfs(), count: Int(count) + 4)
        let filled = buffer.withUnsafeMutableBufferPointer { pointer in
            getfsstat(pointer.baseAddress, Int32(pointer.count * MemoryLayout<statfs>.stride), MNT_NOWAIT)
        }
        guard filled > 0 else { throw DiskReadError.unavailable("macOS did not list any mounted drives.") }
        return Array(buffer.prefix(Int(filled)))
    }

    private static func string<T>(_ tuple: T) -> String {
        withUnsafeBytes(of: tuple) { raw in
            let bytes = raw.prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
        }
    }
}
#else
/// Linux fallback (the root file system only) so the reader can be exercised in CI. MacPeek ships for macOS.
public struct SystemVolumeCapacityReader: VolumeCapacityReading {
    public init() {}

    public func read() throws -> [VolumeCapacity] {
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: "/")
        guard let total = Self.int64(attributes[.systemSize]), let free = Self.int64(attributes[.systemFreeSize]) else {
            throw DiskReadError.unavailable("The root file system did not report its size.")
        }
        return [VolumeCapacity(name: "/", path: "/", totalBytes: total, strictlyFreeBytes: free,
                               availableForImportantUsageBytes: nil, isRoot: true, isInternal: nil, isRemovable: nil)]
    }

    private static func int64(_ value: Any?) -> Int64? {
        switch value {
        case let v as Int64: return v
        case let v as UInt64: return Int64(clamping: v)
        case let v as Int: return Int64(v)
        case let v as NSNumber: return v.int64Value
        default: return nil
        }
    }
}
#endif
