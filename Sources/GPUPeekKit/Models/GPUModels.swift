import Foundation
import MacPeekCore

/// One GPU as the I/O registry describes it (`IOAccelerator` services), with the statistics its driver publishes.
public struct GPUInfo: Identifiable, Equatable, Codable, Sendable {
    public var id: String { registryClass + ":" + name }
    /// "Apple M2 Pro", or the driver class when the registry names no model.
    public let name: String
    /// The driver class, e.g. `AGXAcceleratorG14X`.
    public let registryClass: String
    public let coreCount: Int?
    /// `Device Utilization %`: how busy the GPU was, as its driver last reported it (0–100).
    public let deviceUtilization: Double?
    /// `Renderer Utilization %` and `Tiler Utilization %` (Apple GPUs).
    public let rendererUtilization: Double?
    public let tilerUtilization: Double?
    /// `In use system memory`: memory the GPU is using right now. On Apple silicon this is part of the Mac's unified memory.
    public let memoryInUseBytes: UInt64?
    /// `Alloc system memory`: memory the GPU driver has set aside.
    public let memoryAllocatedBytes: UInt64?
    /// Dedicated video memory on Macs with a separate GPU, when the driver reports it.
    public let vramTotalBytes: UInt64?
    public let vramUsedBytes: UInt64?
    /// True for Apple silicon GPUs, which share the Mac's memory instead of having their own.
    public let unifiedMemory: Bool

    public init(name: String, registryClass: String, coreCount: Int?, deviceUtilization: Double?, rendererUtilization: Double?,
                tilerUtilization: Double?, memoryInUseBytes: UInt64?, memoryAllocatedBytes: UInt64?, vramTotalBytes: UInt64?,
                vramUsedBytes: UInt64?, unifiedMemory: Bool) {
        self.name = name
        self.registryClass = registryClass
        self.coreCount = coreCount
        self.deviceUtilization = deviceUtilization
        self.rendererUtilization = rendererUtilization
        self.tilerUtilization = tilerUtilization
        self.memoryInUseBytes = memoryInUseBytes
        self.memoryAllocatedBytes = memoryAllocatedBytes
        self.vramTotalBytes = vramTotalBytes
        self.vramUsedBytes = vramUsedBytes
        self.unifiedMemory = unifiedMemory
    }

    /// The fraction (0–1) for a ring gauge, when the driver reports utilization.
    public var utilizationFraction: Double? { deviceUtilization.map { min(max($0 / 100, 0), 1) } }
}

/// A process with the GPU open (an `IOAccelerator` user client), and the GPU time macOS has counted for it.
public struct GPUClient: Equatable, Codable, Sendable {
    public let pid: Int
    public let processName: String
    /// Total GPU time in nanoseconds across the client's command queues, when the driver publishes it (`AppUsage`).
    public let gpuTimeNanoseconds: UInt64?

    public init(pid: Int, processName: String, gpuTimeNanoseconds: UInt64?) {
        self.pid = pid
        self.processName = processName
        self.gpuTimeNanoseconds = gpuTimeNanoseconds
    }
}

/// GPU use of one process over the last interval.
public struct GPUProcessUsage: Identifiable, Equatable, Codable, Sendable {
    public var id: Int { pid }
    public let pid: Int
    public let name: String
    /// Percent of the GPU's time used by this process over the interval; nil until two readings exist or when the
    /// driver does not count GPU time per process.
    public let gpuPercent: Double?
    /// How many GPU connections the process has open.
    public let connections: Int

    public init(pid: Int, name: String, gpuPercent: Double?, connections: Int) {
        self.pid = pid
        self.name = name
        self.gpuPercent = gpuPercent
        self.connections = connections
    }
}

/// Power drawn by the CPU, GPU and Neural Engine over the last interval, from macOS's energy counters.
public struct PowerReading: Equatable, Codable, Sendable {
    public let cpuWatts: Double?
    public let gpuWatts: Double?
    /// The Neural Engine's power. macOS publishes no Neural Engine utilization to apps; its power draw is the
    /// observable sign of how hard it is working (0 W when idle).
    public let neuralEngineWatts: Double?
    public let intervalSeconds: Double

    public init(cpuWatts: Double?, gpuWatts: Double?, neuralEngineWatts: Double?, intervalSeconds: Double) {
        self.cpuWatts = cpuWatts
        self.gpuWatts = gpuWatts
        self.neuralEngineWatts = neuralEngineWatts
        self.intervalSeconds = intervalSeconds
    }

    public var neuralEngineActive: Bool? { neuralEngineWatts.map { $0 >= 0.01 } }
}

public struct GPUSnapshot: Equatable, Codable, Sendable {
    public let gpus: [GPUInfo]
    /// Processes with the GPU open, busiest first.
    public let processes: [GPUProcessUsage]
    /// Nil on the first reading (power needs two) or where the counters are unavailable.
    public let power: PowerReading?
    /// Why power is missing, when it is not just the first reading.
    public let powerNote: String?
    /// Whether this Mac has a Neural Engine (every Apple silicon Mac does).
    public let hasNeuralEngine: Bool

    public init(gpus: [GPUInfo], processes: [GPUProcessUsage], power: PowerReading?, powerNote: String?, hasNeuralEngine: Bool) {
        self.gpus = gpus
        self.processes = processes
        self.power = power
        self.powerNote = powerNote
        self.hasNeuralEngine = hasNeuralEngine
    }

    public var primary: GPUInfo? { gpus.first }

    /// "GPU 12%" for the launcher, or the GPU memory when utilization is not reported.
    public var summary: String? {
        guard let gpu = primary else { return nil }
        if let utilization = gpu.deviceUtilization { return "GPU \(Int(utilization.rounded()))%" }
        if let memory = gpu.memoryInUseBytes { return ByteCountText.memory(memory) + " in use" }
        return gpu.name
    }
}
