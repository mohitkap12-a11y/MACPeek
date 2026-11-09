import Foundation
import MacPeekCore

/// What Metal says about a GPU: capabilities and limits, not live load. Read with Apple's public Metal API, which needs no
/// permission.
public struct GPUDeviceFacts: Equatable, Codable, Sendable {
    public let name: String
    /// The GPU shares the Mac's memory (every Apple silicon Mac).
    public let hasUnifiedMemory: Bool
    /// How much memory macOS lets the GPU use before performance suffers (`recommendedMaxWorkingSetSize`).
    public let recommendedMaxWorkingSetBytes: UInt64?
    /// The largest single buffer the GPU can allocate (`maxBufferLength`).
    public let maxBufferBytes: UInt64?
    /// The newest Apple GPU family it supports, e.g. "Apple 9", and whether it supports Metal 3.
    public let gpuFamily: String?
    public let supportsMetal3: Bool
    /// An integrated low-power GPU on an Intel Mac with two GPUs.
    public let isLowPower: Bool
    /// An external GPU that can be unplugged.
    public let isRemovable: Bool

    public init(name: String, hasUnifiedMemory: Bool, recommendedMaxWorkingSetBytes: UInt64?, maxBufferBytes: UInt64?,
                gpuFamily: String?, supportsMetal3: Bool, isLowPower: Bool, isRemovable: Bool) {
        self.name = name
        self.hasUnifiedMemory = hasUnifiedMemory
        self.recommendedMaxWorkingSetBytes = recommendedMaxWorkingSetBytes
        self.maxBufferBytes = maxBufferBytes
        self.gpuFamily = gpuFamily
        self.supportsMetal3 = supportsMetal3
        self.isLowPower = isLowPower
        self.isRemovable = isRemovable
    }
}

/// How GPUPeek reads its numbers: the launcher ring, the memory ring and the headline. Pure functions, tested on Linux.
public enum GPUAssessment {
    /// The share at which the launcher ring turns red.
    public static let alertUtilization = 90.0

    /// The launcher ring: busy % with GPU memory as the caption. Nil when the driver reports no utilization (some Intel
    /// and AMD drivers), so the launcher shows "–" instead of a made-up 0 %.
    public static func gaugeReading(_ gpu: GPUInfo) -> GaugeReading? {
        guard let utilization = gpu.deviceUtilization else { return nil }
        return GaugeReading(fraction: utilization / 100, caption: caption(gpu), isAlert: utilization >= alertUtilization)
    }

    /// "1.2 GB in use", or the VRAM in use, or the GPU's name when the driver reports no memory figure.
    public static func caption(_ gpu: GPUInfo) -> String {
        if let used = gpu.memoryInUseBytes { return ByteCountText.memory(used) + " in use" }
        if let used = gpu.vramUsedBytes { return ByteCountText.memory(used) + " VRAM" }
        return gpu.name
    }

    /// GPU memory in use against what macOS lets the GPU use (unified memory) or the VRAM size. Nil when either is unknown.
    public static func memoryFraction(_ gpu: GPUInfo, facts: GPUDeviceFacts?) -> Double? {
        if let used = gpu.memoryInUseBytes, let limit = facts?.recommendedMaxWorkingSetBytes, limit > 0 {
            return min(Double(used) / Double(limit), 1)
        }
        if let used = gpu.vramUsedBytes, let total = gpu.vramTotalBytes, total > 0 {
            return min(Double(used) / Double(total), 1)
        }
        return nil
    }

    /// A one-line reading for the top of the screen.
    public static func headline(_ gpu: GPUInfo?, power: PowerReading?) -> String {
        guard let gpu else { return "macOS lists no GPU" }
        let ane = power?.neuralEngineActive == true ? " The Neural Engine is working." : ""
        guard let utilization = gpu.deviceUtilization else { return "The GPU driver reports no utilization." + ane }
        switch utilization {
        case ..<5: return "The GPU is idle." + ane
        case ..<50: return "The GPU is lightly used." + ane
        case ..<alertUtilization: return "The GPU is busy." + ane
        default: return "The GPU is fully busy." + ane
        }
    }

    /// The newest Apple GPU family name from the families a device supports (`supports(n)` for Apple family n).
    public static func appleFamily(supports: (Int) -> Bool) -> String? {
        for family in stride(from: 10, through: 1, by: -1) where supports(family) { return "Apple \(family)" }
        return nil
    }
}

/// Reads Metal's facts about the GPU that macOS lists first. Nil where Metal is unavailable (Linux, or no GPU).
public protocol GPUDeviceFactsReading: Sendable {
    func facts() -> [GPUDeviceFacts]
}

#if canImport(Metal)
import Metal

public struct MetalDeviceFactsReader: GPUDeviceFactsReading {
    public init() {}

    public func facts() -> [GPUDeviceFacts] {
        #if os(macOS)
        let devices = MTLCopyAllDevices()
        #else
        let devices = [MTLCreateSystemDefaultDevice()].compactMap { $0 }
        #endif
        return devices.map { device in
            GPUDeviceFacts(name: device.name, hasUnifiedMemory: device.hasUnifiedMemory,
                           recommendedMaxWorkingSetBytes: device.recommendedMaxWorkingSetSize,
                           maxBufferBytes: UInt64(device.maxBufferLength),
                           gpuFamily: GPUAssessment.appleFamily { Self.supports(device, apple: $0) },
                           supportsMetal3: device.supportsFamily(.metal3),
                           isLowPower: device.isLowPower, isRemovable: device.isRemovable)
        }
    }

    private static func supports(_ device: MTLDevice, apple family: Int) -> Bool {
        switch family {
        case 1: return device.supportsFamily(.apple1)
        case 2: return device.supportsFamily(.apple2)
        case 3: return device.supportsFamily(.apple3)
        case 4: return device.supportsFamily(.apple4)
        case 5: return device.supportsFamily(.apple5)
        case 6: return device.supportsFamily(.apple6)
        case 7: return device.supportsFamily(.apple7)
        case 8: return device.supportsFamily(.apple8)
        case 9:
            if #available(macOS 14.0, iOS 17.0, *) { return device.supportsFamily(.apple9) }
            return false
        default: return false
        }
    }
}
#endif
