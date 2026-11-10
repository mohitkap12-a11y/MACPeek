import Foundation
#if canImport(IOKit)
import IOKit
#endif

/// Bytes the physical drive behind one mounted volume has read and written since the drive appeared, as its
/// block-storage driver counts them. Volumes on the same drive (APFS volumes of one container, partitions of one
/// disk) report the same drive and the same counters: macOS counts I/O per drive, not per volume.
public struct VolumeIOCounters: Equatable, Codable, Sendable {
    /// The volume's mount point, matching `VolumeCapacity.path`.
    public let path: String
    /// The drive's BSD name ("disk0", "disk4"), shared by every volume on it.
    public let device: String
    public let bytesRead: UInt64
    public let bytesWritten: UInt64

    public init(path: String, device: String, bytesRead: UInt64, bytesWritten: UInt64) {
        self.path = path
        self.device = device
        self.bytesRead = bytesRead
        self.bytesWritten = bytesWritten
    }
}

/// One drive's read and write speed over the last interval, for one volume on it.
public struct VolumeIORate: Equatable, Codable, Sendable {
    public let path: String
    public let device: String
    public let readBytesPerSecond: Double
    public let writeBytesPerSecond: Double

    public init(path: String, device: String, readBytesPerSecond: Double, writeBytesPerSecond: Double) {
        self.path = path
        self.device = device
        self.readBytesPerSecond = readBytesPerSecond
        self.writeBytesPerSecond = writeBytesPerSecond
    }
}

/// Turns two readings of drive counters into rates. A drive whose counters went down (it was unplugged and plugged
/// back in) starts again from its new reading instead of showing a negative or huge rate.
public struct VolumeIOSampler: Sendable {
    private var last: [String: (device: String, read: UInt64, written: UInt64)] = [:]
    private var lastDate: Date?

    public init() {}

    /// Rates by mount point; empty for the first reading.
    public mutating func ingest(_ counters: [VolumeIOCounters], at date: Date) -> [String: VolumeIORate] {
        defer {
            last = Dictionary(counters.map { ($0.path, (device: $0.device, read: $0.bytesRead, written: $0.bytesWritten)) },
                              uniquingKeysWith: { first, _ in first })
            lastDate = date
        }
        guard let lastDate else { return [:] }
        let elapsed = date.timeIntervalSince(lastDate)
        guard elapsed > 0 else { return [:] }
        var rates: [String: VolumeIORate] = [:]
        for counter in counters {
            guard let previous = last[counter.path], previous.device == counter.device,
                  counter.bytesRead >= previous.read, counter.bytesWritten >= previous.written else { continue }
            rates[counter.path] = VolumeIORate(path: counter.path, device: counter.device,
                                               readBytesPerSecond: Double(counter.bytesRead - previous.read) / elapsed,
                                               writeBytesPerSecond: Double(counter.bytesWritten - previous.written) / elapsed)
        }
        return rates
    }
}

/// BSD media names: "disk3s1s1" is a slice of "disk3s1", itself a slice of "disk3".
enum VolumeIOName {
    static func parent(of name: String) -> String? {
        guard let range = name.range(of: "s[0-9]+$", options: .regularExpression),
              name[..<range.lowerBound].range(of: "^disk[0-9]+", options: .regularExpression) != nil else { return nil }
        return String(name[..<range.lowerBound])
    }
}

public protocol VolumeIOReading: Sendable {
    /// Counters for the drive behind each volume `VolumeCapacityReading` lists; volumes whose drive does not report
    /// statistics (disk images, network mounts) are left out.
    func read() throws -> [VolumeIOCounters]
}

#if canImport(IOKit)
/// Finds each volume's drive by walking up the I/O Registry from the volume's media to the first block-storage driver,
/// and reads that driver's "Statistics". For an APFS volume the walk passes through its container to the physical
/// store, so the startup volume reports the internal SSD and a volume on an external drive reports that drive. Reads
/// the registry only (no disk is touched or woken), cheap enough for every refresh.
public struct SystemVolumeIOReader: VolumeIOReading {
    public init() {}

    public func read() throws -> [VolumeIOCounters] {
        var result: [VolumeIOCounters] = []
        var byMedia: [String: (device: String, read: UInt64, written: UInt64)?] = [:]
        for mount in try SystemVolumeCapacityReader.mounts() where SystemVolumeCapacityReader.isListed(mount) {
            let source = SystemVolumeCapacityReader.string(mount.f_mntfromname)
            guard source.hasPrefix("/dev/") else { continue }
            let media = String(source.dropFirst(5))
            let statistics: (device: String, read: UInt64, written: UInt64)?
            if let cached = byMedia[media] {
                statistics = cached
            } else {
                statistics = Self.statistics(media: media)
                byMedia[media] = statistics
            }
            guard let statistics else { continue }
            result.append(VolumeIOCounters(path: SystemVolumeCapacityReader.string(mount.f_mntonname), device: statistics.device,
                                           bytesRead: statistics.read, bytesWritten: statistics.written))
        }
        return result
    }

    /// The statistics for `media`, or for the slice or disk it is part of when the registry has no entry for it (the
    /// startup disk's sealed snapshot, "disk3s1s1", is looked up as "disk3s1", then "disk3").
    static func statistics(media: String) -> (device: String, read: UInt64, written: UInt64)? {
        var name = media
        while true {
            if let found = statistics(exactly: name) { return found }
            guard let parent = VolumeIOName.parent(of: name) else { return nil }
            name = parent
        }
    }

    private static func statistics(exactly media: String) -> (device: String, read: UInt64, written: UInt64)? {
        guard let matching = IOBSDNameMatching(kIOMainPortDefault, 0, media) else { return nil }
        // IOServiceGetMatchingService consumes `matching`.
        var entry = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        var wholeDisk: String?
        while entry != 0 {
            if IOObjectConformsTo(entry, "IOMedia") != 0, property(entry, "Whole") as? Bool == true,
               let name = property(entry, "BSD Name") as? String {
                // The last whole disk below the driver is the physical drive (an APFS container's synthesized disk
                // comes first on the way up).
                wholeDisk = name
            }
            if IOObjectConformsTo(entry, "IOBlockStorageDriver") != 0 {
                let statistics = property(entry, "Statistics") as? [String: Any]
                IOObjectRelease(entry)
                guard let statistics, let read = number(statistics["Bytes (Read)"]),
                      let written = number(statistics["Bytes (Write)"]) else { return nil }
                return (wholeDisk ?? media, read, written)
            }
            var parent: io_registry_entry_t = 0
            let status = IORegistryEntryGetParentEntry(entry, "IOService", &parent)
            IOObjectRelease(entry)
            entry = status == KERN_SUCCESS ? parent : 0
        }
        return nil
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private static func number(_ value: Any?) -> UInt64? {
        (value as? NSNumber)?.uint64Value
    }
}
#else
/// Linux has no I/O Registry; drive statistics are a macOS feature.
public struct SystemVolumeIOReader: VolumeIOReading {
    public init() {}
    public func read() throws -> [VolumeIOCounters] { [] }
}
#endif
