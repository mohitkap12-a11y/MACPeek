import Foundation
import MacPeekCore

/// Parses `ioreg -r -d 2 -c IOAccelerator -a -w0`: a property list array with one dictionary per GPU, whose
/// `IORegistryEntryChildren` are the per-process user clients. Every field is optional: drivers publish different keys.
public enum IORegGPUParser {
    public struct Result: Equatable, Sendable {
        public let gpus: [GPUInfo]
        public let clients: [GPUClient]
    }

    public static func parse(_ data: Data) -> Result? {
        guard let root = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else { return nil }
        let entries: [[String: Any]]
        if let array = root as? [Any] { entries = array.compactMap { $0 as? [String: Any] } }
        else if let single = root as? [String: Any] { entries = [single] }
        else { return nil }
        var gpus: [GPUInfo] = []
        var clients: [GPUClient] = []
        for entry in entries {
            gpus.append(gpu(from: entry))
            for child in (entry["IORegistryEntryChildren"] as? [Any] ?? []).compactMap({ $0 as? [String: Any] }) {
                if let client = client(from: child) { clients.append(client) }
            }
        }
        return Result(gpus: gpus, clients: clients)
    }

    public static func parse(_ text: String) -> Result? { parse(Data(text.utf8)) }

    static func gpu(from entry: [String: Any]) -> GPUInfo {
        let registryClass = string(entry["IOClass"]) ?? string(entry["IOObjectClass"]) ?? "GPU"
        let stats = entry["PerformanceStatistics"] as? [String: Any] ?? [:]
        let name = string(entry["model"]) ?? string(entry["IOGLBundleName"]) ?? registryClass
        let apple = registryClass.hasPrefix("AGX") || name.hasPrefix("Apple ")
        var vramTotal = number(stats["vramUsedBytes"]).flatMap { used in number(stats["vramFreeBytes"]).map { used + $0 } }
        if vramTotal == nil, let megabytes = number(entry["VRAM,totalMB"]) { vramTotal = megabytes * 1_048_576 }
        return GPUInfo(
            name: name, registryClass: registryClass, coreCount: number(entry["gpu-core-count"]).map(Int.init),
            deviceUtilization: double(stats["Device Utilization %"]) ?? double(stats["GPU Activity(%)"]),
            rendererUtilization: double(stats["Renderer Utilization %"]),
            tilerUtilization: double(stats["Tiler Utilization %"]),
            memoryInUseBytes: number(stats["In use system memory"]),
            memoryAllocatedBytes: number(stats["Alloc system memory"]),
            vramTotalBytes: apple ? nil : vramTotal,
            vramUsedBytes: apple ? nil : number(stats["vramUsedBytes"]),
            unifiedMemory: apple)
    }

    private static let creator = NSRegularExpression.compile(#"^pid\s+(\d+),\s*(.+)$"#)

    /// A user client says who opened it as `IOUserClientCreator = "pid 412, WindowServer"`; Apple GPUs also list
    /// `AppUsage`, one entry per command queue with its `accumulatedGPUTime` in nanoseconds.
    static func client(from entry: [String: Any]) -> GPUClient? {
        guard let text = string(entry["IOUserClientCreator"]), let g = creator.groups(in: text),
              let pid = g[1].flatMap(Int.init), let name = g[2] else { return nil }
        let usage = (entry["AppUsage"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
        let times = usage.compactMap { number($0["accumulatedGPUTime"]) }
        return GPUClient(pid: pid, processName: name.trimmingCharacters(in: .whitespaces),
                         gpuTimeNanoseconds: times.isEmpty ? nil : times.reduce(0, +))
    }

    static func string(_ value: Any?) -> String? {
        switch value {
        case let text as String:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0")))
            return trimmed.isEmpty ? nil : trimmed
        case let data as Data:
            return string(String(decoding: data, as: UTF8.self))
        default: return nil
        }
    }

    static func number(_ value: Any?) -> UInt64? {
        switch value {
        case let n as Int: return n >= 0 ? UInt64(n) : nil
        case let n as UInt64: return n
        case let n as Int64: return n >= 0 ? UInt64(n) : nil
        case let n as Double: return n >= 0 && n < 1.8e19 ? UInt64(n) : nil
        case let n as NSNumber: return n.int64Value >= 0 ? UInt64(n.int64Value) : nil
        default: return nil
        }
    }

    static func double(_ value: Any?) -> Double? {
        switch value {
        case let n as Int: return Double(n)
        case let n as Double: return n
        case let n as UInt64: return Double(n)
        case let n as Int64: return Double(n)
        case let n as NSNumber: return n.doubleValue
        default: return nil
        }
    }
}

/// Per-process GPU share from two readings of the clients' accumulated GPU time. Several clients of one process are
/// added together. The share is of one GPU's time, so it is comparable to the GPU's own utilization.
public enum GPUClientSampling {
    public static func usage(current: [GPUClient], previous: [GPUClient]?, interval: TimeInterval) -> [GPUProcessUsage] {
        let now = totals(current)
        let before = previous.map(totals)
        var result: [GPUProcessUsage] = now.map { pid, entry in
            var percent: Double?
            if interval > 0, let time = entry.time, let old = before?[pid], old.name == entry.name, let oldTime = old.time, time >= oldTime {
                percent = min(Double(time - oldTime) / (interval * 1_000_000_000) * 100, 100)
            }
            return GPUProcessUsage(pid: pid, name: entry.name, gpuPercent: percent, connections: entry.count)
        }
        result.sort { lhs, rhs in
            let l = lhs.gpuPercent ?? -1, r = rhs.gpuPercent ?? -1
            return l != r ? l > r : (lhs.connections != rhs.connections ? lhs.connections > rhs.connections : lhs.pid < rhs.pid)
        }
        return result
    }

    static func totals(_ clients: [GPUClient]) -> [Int: (name: String, time: UInt64?, count: Int)] {
        var result: [Int: (name: String, time: UInt64?, count: Int)] = [:]
        for client in clients {
            var entry = result[client.pid] ?? (client.processName, nil, 0)
            entry.count += 1
            if let time = client.gpuTimeNanoseconds { entry.time = (entry.time ?? 0) &+ time }
            result[client.pid] = entry
        }
        return result
    }
}

/// Turns energy counters (millijoules, microjoules or nanojoules per channel, as IOReport labels them) into watts.
public enum EnergyMath {
    public enum Component { case cpu, gpu, neuralEngine }

    /// Which component an `Energy Model` channel belongs to. Per-cluster CPU channels ("ECPU0", "PCPU1"…) are skipped
    /// in favour of the "CPU Energy" total, so nothing is counted twice.
    public static func component(ofChannel name: String) -> Component? {
        if name == "CPU Energy" { return .cpu }
        if name == "GPU Energy" || name == "GPU" { return .gpu }
        if name.hasPrefix("ANE") { return .neuralEngine }
        return nil
    }

    public static func joules(_ value: Int64, unit: String) -> Double? {
        switch unit.trimmingCharacters(in: .whitespaces) {
        case "mJ": return Double(value) / 1_000
        case "uJ", "µJ": return Double(value) / 1_000_000
        case "nJ": return Double(value) / 1_000_000_000
        case "J": return Double(value)
        default: return nil
        }
    }

    /// Adds the channels up per component and divides by the interval.
    public static func reading(channels: [(name: String, value: Int64, unit: String)], interval: TimeInterval) -> PowerReading? {
        guard interval > 0 else { return nil }
        var totals: [Component: Double] = [:]
        for channel in channels {
            guard let component = component(ofChannel: channel.name), let joules = joules(channel.value, unit: channel.unit) else { continue }
            totals[component, default: 0] += joules
        }
        guard !totals.isEmpty else { return nil }
        return PowerReading(cpuWatts: totals[.cpu].map { $0 / interval }, gpuWatts: totals[.gpu].map { $0 / interval },
                            neuralEngineWatts: totals[.neuralEngine].map { $0 / interval }, intervalSeconds: interval)
    }
}
