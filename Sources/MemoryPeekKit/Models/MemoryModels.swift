import Foundation

/// How hard macOS is working to find memory, as the kernel reports it. This, not "free memory", says whether a Mac is
/// short of RAM: macOS fills spare memory with cached files on purpose.
public enum MemoryPressure: String, Equatable, Sendable {
    case normal = "Normal"
    case warning = "Warning"
    case critical = "Critical"

    /// `kern.memorystatus_vm_pressure_level` reports the dispatch levels: 1 normal, 2 warning, 4 critical.
    public init?(sysctlLevel: Int32) {
        switch sysctlLevel {
        case 1: self = .normal
        case 2: self = .warning
        case 4: self = .critical
        default: return nil
        }
    }
}

/// Raw page counts from `host_statistics64(HOST_VM_INFO64)` plus the totals around them.
public struct MemoryStats: Equatable, Sendable {
    public let physicalBytes: UInt64
    public let pageSize: UInt64
    public let freePages: UInt64
    public let activePages: UInt64
    public let inactivePages: UInt64
    public let speculativePages: UInt64
    public let wiredPages: UInt64
    /// Pages the compressor occupies (the compressed data itself, not what it holds).
    public let compressorPages: UInt64
    public let purgeablePages: UInt64
    /// File-backed pages (cached files).
    public let externalPages: UInt64
    /// Anonymous pages (app memory).
    public let internalPages: UInt64
    public let swapUsedBytes: UInt64?
    public let swapTotalBytes: UInt64?
    public let pressure: MemoryPressure?
    /// `kern.memorystatus_level`: the percentage of memory macOS considers available.
    public let availablePercent: Int?

    public init(physicalBytes: UInt64, pageSize: UInt64, freePages: UInt64, activePages: UInt64, inactivePages: UInt64,
                speculativePages: UInt64, wiredPages: UInt64, compressorPages: UInt64, purgeablePages: UInt64,
                externalPages: UInt64, internalPages: UInt64, swapUsedBytes: UInt64?, swapTotalBytes: UInt64?,
                pressure: MemoryPressure?, availablePercent: Int?) {
        self.physicalBytes = physicalBytes
        self.pageSize = pageSize
        self.freePages = freePages
        self.activePages = activePages
        self.inactivePages = inactivePages
        self.speculativePages = speculativePages
        self.wiredPages = wiredPages
        self.compressorPages = compressorPages
        self.purgeablePages = purgeablePages
        self.externalPages = externalPages
        self.internalPages = internalPages
        self.swapUsedBytes = swapUsedBytes
        self.swapTotalBytes = swapTotalBytes
        self.pressure = pressure
        self.availablePercent = availablePercent
    }
}

/// Memory split the way Activity Monitor's Memory tab splits it.
public struct MemoryBreakdown: Equatable, Sendable {
    public let physical: UInt64
    /// App memory: anonymous pages that cannot simply be dropped (internal − purgeable).
    public let app: UInt64
    /// Wired: kept by macOS itself and never compressed or moved to disk.
    public let wired: UInt64
    public let compressed: UInt64
    /// Cached files: file-backed and purgeable pages macOS gives back as soon as apps need room.
    public let cachedFiles: UInt64
    /// Not in use at all.
    public let free: UInt64

    /// App + wired + compressed: what Activity Monitor calls Memory Used.
    public var used: UInt64 { app &+ wired &+ compressed }

    public init(_ stats: MemoryStats) {
        let page = stats.pageSize
        let appPages = stats.internalPages > stats.purgeablePages ? stats.internalPages - stats.purgeablePages : 0
        physical = stats.physicalBytes
        app = appPages &* page
        wired = stats.wiredPages &* page
        compressed = stats.compressorPages &* page
        cachedFiles = (stats.externalPages &+ stats.purgeablePages) &* page
        let accounted = app &+ wired &+ compressed &+ cachedFiles
        free = stats.physicalBytes > accounted ? stats.physicalBytes - accounted : 0
    }
}

/// One process's memory footprint, for the "using the most memory" list.
public struct ProcessMemoryRow: Identifiable, Equatable, Sendable {
    public var id: Int { pid }
    public let pid: Int
    public let name: String
    public let footprintBytes: UInt64

    public init(pid: Int, name: String, footprintBytes: UInt64) {
        self.pid = pid
        self.name = name
        self.footprintBytes = footprintBytes
    }
}

public enum MemoryReadError: Error, LocalizedError, Equatable {
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let detail): return detail
        }
    }
}
