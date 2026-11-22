import Foundation

/// What a temperature sensor measures, worked out from the name macOS gives it.
public enum SensorGroup: String, Codable, Sendable, CaseIterable {
    case cpu, gpu, soc, neuralEngine, memory, storage, battery, ambient, other

    public var title: String {
        switch self {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .soc: return "Chip"
        case .neuralEngine: return "Neural Engine"
        case .memory: return "Memory"
        case .storage: return "Storage"
        case .battery: return "Battery"
        case .ambient: return "Ambient"
        case .other: return "Other"
        }
    }
}

public struct TemperatureSensor: Identifiable, Equatable, Codable, Sendable {
    public var id: String { name }
    /// The name macOS reports ("pACC MTR Temp Sensor0", "TC0P").
    public let name: String
    public let group: SensorGroup
    public let celsius: Double

    public init(name: String, group: SensorGroup, celsius: Double) {
        self.name = name
        self.group = group
        self.celsius = celsius
    }
}

public struct FanReading: Identifiable, Equatable, Codable, Sendable {
    public var id: Int { index }
    public let index: Int
    public let rpm: Double
    public let minimumRPM: Double?
    public let maximumRPM: Double?

    public init(index: Int, rpm: Double, minimumRPM: Double?, maximumRPM: Double?) {
        self.index = index
        self.rpm = rpm
        self.minimumRPM = minimumRPM
        self.maximumRPM = maximumRPM
    }

    /// How fast the fan spins between its minimum and maximum, 0...1, when both are known.
    public var fraction: Double? {
        guard let low = minimumRPM, let high = maximumRPM, high > low else { return nil }
        return min(max((rpm - low) / (high - low), 0), 1)
    }
}

/// One reading of the Mac's sensors. Empty lists mean the Mac reports none (or the interfaces are unavailable), and
/// `note` says why when it is not obvious.
public struct SensorSnapshot: Equatable, Codable, Sendable {
    public let temperatures: [TemperatureSensor]
    public let fans: [FanReading]
    /// Whole-Mac power draw (the SMC's system power), watts.
    public let systemWatts: Double?
    public let note: String?

    public init(temperatures: [TemperatureSensor], fans: [FanReading], systemWatts: Double? = nil, note: String? = nil) {
        self.temperatures = temperatures
        self.fans = fans
        self.systemWatts = systemWatts
        self.note = note
    }

    public static let empty = SensorSnapshot(temperatures: [], fans: [])

    public var isEmpty: Bool { temperatures.isEmpty && fans.isEmpty && systemWatts == nil }

    /// The hottest sensor in a group.
    public func hottest(_ group: SensorGroup) -> Double? {
        temperatures.filter { $0.group == group }.map(\.celsius).max()
    }

    public func average(_ group: SensorGroup) -> Double? {
        let values = temperatures.filter { $0.group == group }.map(\.celsius)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// The number the menu bar, the history and the launcher show: the hottest CPU sensor, or the chip's when the Mac
    /// does not name CPU sensors.
    public var headlineCelsius: Double? { hottest(.cpu) ?? hottest(.soc) }

    /// Groups with at least one sensor, in a fixed order, with their hottest and average readings.
    public var summary: [SensorSummary] {
        SensorGroup.allCases.compactMap { group in
            let values = temperatures.filter { $0.group == group }.map(\.celsius)
            guard let hottest = values.max() else { return nil }
            return SensorSummary(group: group, hottest: hottest, average: values.reduce(0, +) / Double(values.count),
                                 count: values.count)
        }
    }
}

/// One group's temperatures: the hottest and average of its sensors.
public struct SensorSummary: Identifiable, Equatable, Sendable {
    public var id: SensorGroup { group }
    public let group: SensorGroup
    public let hottest: Double
    public let average: Double
    public let count: Int
}

/// Where a sensor name comes from tells what it measures. Apple silicon's HID sensors have descriptive names; Intel's
/// SMC keys follow a well-known scheme (TC = CPU, TG = GPU, TB = battery, TA = ambient, TM = memory, TH = drive).
public enum SensorClassifier {
    public static func group(forHIDName name: String) -> SensorGroup {
        let lower = name.lowercased()
        if lower.contains("pacc") || lower.contains("eacc") || lower.contains("tdie") || lower.contains("cpu") { return .cpu }
        if lower.contains("gpu") { return .gpu }
        if lower.contains("ane") { return .neuralEngine }
        if lower.contains("nand") || lower.contains("ssd") { return .storage }
        if lower.contains("battery") || lower.contains("gas gauge") { return .battery }
        if lower.contains("soc") || lower.contains("pmgr") || lower.contains("tdev") || lower.contains("pmu") { return .soc }
        if lower.contains("dram") || lower.contains("mem") { return .memory }
        if lower.contains("ambient") || lower.contains("airflow") { return .ambient }
        return .other
    }

    public static func group(forSMCKey key: String) -> SensorGroup {
        guard key.count == 4, key.hasPrefix("T") else { return .other }
        let kind = String(key.dropFirst().prefix(1))
        switch kind {
        case "C": return .cpu
        case "G": return .gpu
        case "B": return .battery
        case "A": return .ambient
        case "M": return .memory
        case "H": return .storage
        case "P", "N": return .soc
        default: return .other
        }
    }

    /// Below 1 °C or above 130 °C a sensor is not reporting a temperature (disconnected, or a placeholder value).
    public static func isPlausible(_ celsius: Double) -> Bool { celsius.isFinite && celsius >= 1 && celsius <= 130 }
}

/// Decodes values read from the SMC. Each key has a four-character type; the bytes are the value in that type.
public enum SMCValue {
    /// The SMC's four-character codes as 32-bit numbers ("TC0P" → 0x54433050).
    public static func code(_ text: String) -> UInt32 {
        text.utf8.prefix(4).reduce(0) { $0 << 8 | UInt32($1) }
    }

    public static func text(_ code: UInt32) -> String {
        let bytes = [UInt8(code >> 24 & 0xff), UInt8(code >> 16 & 0xff), UInt8(code >> 8 & 0xff), UInt8(code & 0xff)]
        return String(decoding: bytes, as: UTF8.self)
    }

    /// The value as a number, or nil for a type MacPeek does not read.
    public static func decode(type: String, bytes: [UInt8]) -> Double? {
        switch type {
        case "flt ":
            // Apple silicon: a little-endian 32-bit float.
            guard bytes.count >= 4 else { return nil }
            let raw = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            return Double(Float(bitPattern: raw))
        case "fpe2":
            // Unsigned fixed point, 14 integer bits and 2 fraction bits, big-endian (Intel fan speeds).
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        case "sp78":
            // Signed fixed point, 7 integer bits and 8 fraction bits, big-endian (Intel temperatures).
            guard bytes.count >= 2 else { return nil }
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        case "ui8 ":
            guard bytes.count >= 1 else { return nil }
            return Double(bytes[0])
        case "ui16":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32":
            guard bytes.count >= 4 else { return nil }
            return Double(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))
        default:
            return nil
        }
    }
}

public protocol SensorReading: Sendable {
    /// Temperatures, fans and power. Cheap (no process is started), so the background monitor may call it every few
    /// seconds. Never throws: whatever cannot be read is left out.
    func read() -> SensorSnapshot
}
