import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Bytes received and sent by one network interface since it came up, as the kernel counts them.
public struct InterfaceCounters: Equatable, Codable, Sendable {
    public let name: String
    public let bytesIn: UInt64
    public let bytesOut: UInt64

    public init(name: String, bytesIn: UInt64, bytesOut: UInt64) {
        self.name = name
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
    }

    /// Loopback, VPN tunnels, bridges and Apple's peer-to-peer links. Their traffic either never leaves the Mac or also
    /// crosses a physical interface, so the totals leave them out to avoid counting it twice.
    public var isVirtual: Bool {
        ["lo", "utun", "ipsec", "gif", "stf", "awdl", "llw", "bridge", "ap", "anpi", "vmenet", "docker", "veth"]
            .contains { name.hasPrefix($0) }
    }
}

/// One interface's traffic over the last sampling interval, in bytes per second.
public struct InterfaceThroughput: Identifiable, Equatable, Codable, Sendable {
    public var id: String { name }
    public let name: String
    public let inBytesPerSecond: Double
    public let outBytesPerSecond: Double
    public let isVirtual: Bool

    public init(name: String, inBytesPerSecond: Double, outBytesPerSecond: Double, isVirtual: Bool) {
        self.name = name
        self.inBytesPerSecond = inBytesPerSecond
        self.outBytesPerSecond = outBytesPerSecond
        self.isVirtual = isVirtual
    }
}

/// Network traffic over the last sampling interval.
public struct NetworkThroughput: Equatable, Codable, Sendable {
    public let interfaces: [InterfaceThroughput]
    public let intervalSeconds: TimeInterval

    public init(interfaces: [InterfaceThroughput], intervalSeconds: TimeInterval) {
        self.interfaces = interfaces
        self.intervalSeconds = intervalSeconds
    }

    /// Download rate across physical interfaces.
    public var inBytesPerSecond: Double { interfaces.filter { !$0.isVirtual }.reduce(0) { $0 + $1.inBytesPerSecond } }
    /// Upload rate across physical interfaces.
    public var outBytesPerSecond: Double { interfaces.filter { !$0.isVirtual }.reduce(0) { $0 + $1.outBytesPerSecond } }
}

/// Turns consecutive counter readings into rates. The first reading is only a baseline.
public struct TrafficSampler: Sendable {
    private var previous: [String: InterfaceCounters] = [:]
    private var previousDate: Date?

    public init() {}

    /// True until a second reading has produced a first set of rates.
    public var isBaselineOnly: Bool { previousDate == nil }

    /// Rates since the previous reading, or nil for the first one (or if the clock did not move forward, in which case
    /// this reading becomes the new baseline). An interface that just appeared gets rates from the next reading on.
    public mutating func ingest(_ counters: [InterfaceCounters], at date: Date) -> NetworkThroughput? {
        defer {
            self.previous = Dictionary(counters.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
            self.previousDate = date
        }
        guard let previousDate, date > previousDate else { return nil }
        let seconds = date.timeIntervalSince(previousDate)
        let rates = counters.compactMap { current -> InterfaceThroughput? in
            guard let before = previous[current.name] else { return nil }
            return InterfaceThroughput(name: current.name,
                                       inBytesPerSecond: Double(Self.delta(current.bytesIn, since: before.bytesIn)) / seconds,
                                       outBytesPerSecond: Double(Self.delta(current.bytesOut, since: before.bytesOut)) / seconds,
                                       isVirtual: current.isVirtual)
        }
        return NetworkThroughput(interfaces: rates.sorted { $0.name < $1.name }, intervalSeconds: seconds)
    }

    /// macOS keeps 32-bit byte counters per interface, so a count that went down wrapped past 4 GiB. A count above
    /// 32 bits that went down was reset (the interface restarted): that interval counts as zero rather than a spike.
    static func delta(_ current: UInt64, since previous: UInt64) -> UInt64 {
        if current >= previous { return current - previous }
        let limit = UInt64(UInt32.max)
        guard previous <= limit, current <= limit else { return 0 }
        return current + (limit + 1 - previous)
    }
}

public protocol InterfaceCountersReading: Sendable {
    /// One `getifaddrs` call: cheap, read-only and needs no permission.
    func read() throws -> [InterfaceCounters]
}

#if canImport(Darwin)
/// Reads the link-level entries of `getifaddrs`, whose `if_data` holds the byte counters.
public struct SystemInterfaceCountersReader: InterfaceCountersReading {
    public init() {}

    public func read() throws -> [InterfaceCounters] {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let start = first else {
            throw NetError.unavailable("macOS did not list the network interfaces.")
        }
        defer { freeifaddrs(first) }
        var result: [InterfaceCounters] = []
        var seen = Set<String>()
        for pointer in sequence(first: start, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let address = entry.ifa_addr, Int32(address.pointee.sa_family) == AF_LINK, let data = entry.ifa_data else { continue }
            let name = String(cString: entry.ifa_name)
            guard seen.insert(name).inserted else { continue }
            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            result.append(InterfaceCounters(name: name, bytesIn: UInt64(stats.ifi_ibytes), bytesOut: UInt64(stats.ifi_obytes)))
        }
        return result
    }
}
#else
/// Linux reader (`/proc/net/dev`) so the sampler can be exercised in CI. MacPeek itself ships for macOS.
public struct SystemInterfaceCountersReader: InterfaceCountersReading {
    public init() {}

    public func read() throws -> [InterfaceCounters] {
        guard let text = try? String(contentsOfFile: "/proc/net/dev", encoding: .utf8) else {
            throw NetError.unavailable("/proc/net/dev is not readable.")
        }
        return Self.parse(text)
    }

    /// Lines after the two header lines look like "  eth0: 1234 5 0 0 0 0 0 0 5678 9 …": received bytes first, sent
    /// bytes ninth.
    static func parse(_ text: String) -> [InterfaceCounters] {
        text.split(separator: "\n").dropFirst(2).compactMap { line in
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            let fields = parts[1].split(separator: " ")
            guard fields.count >= 9, let received = UInt64(fields[0]), let sent = UInt64(fields[8]) else { return nil }
            return InterfaceCounters(name: parts[0].trimmingCharacters(in: .whitespaces), bytesIn: received, bytesOut: sent)
        }
    }
}
#endif
