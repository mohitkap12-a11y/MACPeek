import Foundation
import MemoryPeekKit
import CPUPeekKit

/// One reading of the whole Mac, taken by the background monitor that drives alerts, the menu-bar readout and the
/// 24-hour history. Every value is optional: a reading macOS refused (or a sensor this Mac does not have) is missing,
/// never zero.
public struct VitalsSample: Equatable, Codable, Sendable {
    public var time: Date
    /// Overall CPU use, 0...1.
    public var cpu: Double?
    /// App + wired + compressed memory as a fraction of physical memory, 0...1 (Activity Monitor's "Memory Used").
    public var memoryUsed: Double?
    public var pressure: MemoryPressure?
    public var swapUsedBytes: UInt64?
    /// Physical interfaces only, bytes per second.
    public var networkIn: Double?
    public var networkOut: Double?
    /// The busiest GPU's utilization, 0...1.
    public var gpu: Double?
    /// The hottest CPU or SoC sensor, °C.
    public var temperature: Double?
    /// Whole-Mac power draw, watts, where the Mac reports it.
    public var power: Double?
    public var thermal: ThermalLevel?

    public init(time: Date, cpu: Double? = nil, memoryUsed: Double? = nil, pressure: MemoryPressure? = nil,
                swapUsedBytes: UInt64? = nil, networkIn: Double? = nil, networkOut: Double? = nil, gpu: Double? = nil,
                temperature: Double? = nil, power: Double? = nil, thermal: ThermalLevel? = nil) {
        self.time = time
        self.cpu = cpu
        self.memoryUsed = memoryUsed
        self.pressure = pressure
        self.swapUsedBytes = swapUsedBytes
        self.networkIn = networkIn
        self.networkOut = networkOut
        self.gpu = gpu
        self.temperature = temperature
        self.power = power
        self.thermal = thermal
    }
}

/// What a history chart can plot.
public enum VitalsMetric: String, CaseIterable, Codable, Sendable, Identifiable {
    case cpu, memory, networkIn, networkOut, gpu, temperature, power

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "Memory used"
        case .networkIn: return "Download"
        case .networkOut: return "Upload"
        case .gpu: return "GPU"
        case .temperature: return "Temperature"
        case .power: return "Power"
        }
    }

    /// Fractions are plotted on a fixed 0...1 scale; the others scale to their own maximum.
    public var isFraction: Bool { self == .cpu || self == .memory || self == .gpu }
}
