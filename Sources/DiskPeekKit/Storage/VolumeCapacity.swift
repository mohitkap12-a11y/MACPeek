import Foundation

/// How full one mounted drive is, as macOS reports it.
public struct VolumeCapacity: Identifiable, Equatable, Sendable {
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
    /// Local, visible mounted volumes. Network volumes are skipped so an unresponsive server cannot stall DiskPeek.
    func read() throws -> [VolumeCapacity]
}

#if canImport(Darwin)
public struct SystemVolumeCapacityReader: VolumeCapacityReading {
    public init() {}

    public func read() throws -> [VolumeCapacity] {
        // Ask only for the cheap local/browsable flags first; capacity is read for local volumes only.
        let probe: [URLResourceKey] = [.volumeIsLocalKey, .volumeIsBrowsableKey]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: probe,
                                                               options: [.skipHiddenVolumes]) else {
            throw DiskReadError.unavailable("macOS did not list any mounted drives.")
        }
        var volumes: [VolumeCapacity] = []
        for url in urls {
            guard let flags = try? url.resourceValues(forKeys: Set(probe)),
                  flags.volumeIsLocal == true, flags.volumeIsBrowsable != false else { continue }
            let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
                                             .volumeAvailableCapacityForImportantUsageKey, .volumeIsInternalKey,
                                             .volumeIsRemovableKey, .volumeIsRootFileSystemKey]
            guard let values = try? url.resourceValues(forKeys: keys),
                  let total = values.volumeTotalCapacity, total > 0,
                  let free = values.volumeAvailableCapacity else { continue }
            volumes.append(VolumeCapacity(
                name: values.volumeName ?? url.lastPathComponent, path: url.path,
                totalBytes: Int64(total), strictlyFreeBytes: Int64(free),
                availableForImportantUsageBytes: values.volumeAvailableCapacityForImportantUsage,
                isRoot: values.volumeIsRootFileSystem ?? (url.path == "/"),
                isInternal: values.volumeIsInternal, isRemovable: values.volumeIsRemovable))
        }
        return VolumeCapacity.ordered(volumes)
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
