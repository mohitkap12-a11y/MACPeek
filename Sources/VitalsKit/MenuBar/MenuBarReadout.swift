import Foundation
import MemoryPeekKit

/// What the optional menu-bar readout can show next to (or instead of) MacPeek's icon.
public enum MenuBarMetric: String, CaseIterable, Codable, Sendable, Identifiable {
    case cpu, memory, network, gpu, temperature

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .network: return "Network ↓↑"
        case .gpu: return "GPU"
        case .temperature: return "Temperature"
        }
    }
}

/// How a readout item should be coloured: plain, or warning/critical when the value needs attention.
public enum ReadoutLevel: String, Equatable, Sendable {
    case normal, warning, critical
}

/// One item of the readout, e.g. "CPU 42%".
public struct ReadoutItem: Equatable, Sendable {
    public let metric: MenuBarMetric
    /// A short label ("CPU", "MEM", "GPU"), or nil when the value explains itself (network, temperature).
    public let label: String?
    public let value: String
    public let level: ReadoutLevel

    public init(metric: MenuBarMetric, label: String?, value: String, level: ReadoutLevel = .normal) {
        self.metric = metric
        self.label = label
        self.value = value
        self.level = level
    }
}

/// Turns the latest reading into the readout's items. Values keep a fixed width ("  7%", " 42%") so the menu bar does
/// not jump as they change; a value not read yet shows "–".
public enum MenuBarReadout {
    public static func items(for metrics: [MenuBarMetric], sample: VitalsSample?) -> [ReadoutItem] {
        metrics.map { metric in
            switch metric {
            case .cpu:
                let value = sample?.cpu
                return ReadoutItem(metric: .cpu, label: "CPU", value: percent(value), level: level(value, warning: 0.7, critical: 0.9))
            case .memory:
                let level: ReadoutLevel
                switch sample?.pressure {
                case .critical: level = .critical
                case .warning: level = .warning
                default: level = .normal
                }
                return ReadoutItem(metric: .memory, label: "MEM", value: percent(sample?.memoryUsed), level: level)
            case .network:
                guard let down = sample?.networkIn, let up = sample?.networkOut else {
                    return ReadoutItem(metric: .network, label: nil, value: "↓ –  ↑ –")
                }
                return ReadoutItem(metric: .network, label: nil, value: "↓\(rate(down)) ↑\(rate(up))")
            case .gpu:
                let value = sample?.gpu
                return ReadoutItem(metric: .gpu, label: "GPU", value: percent(value), level: level(value, warning: 0.7, critical: 0.9))
            case .temperature:
                guard let celsius = sample?.temperature else { return ReadoutItem(metric: .temperature, label: nil, value: "–°") }
                return ReadoutItem(metric: .temperature, label: nil, value: "\(Int(celsius.rounded()))°",
                                   level: celsius >= 95 ? .critical : celsius >= 85 ? .warning : .normal)
            }
        }
    }

    /// The whole readout as one line, for the accessibility label and the tooltip.
    public static func spokenText(_ items: [ReadoutItem]) -> String {
        items.map { item in
            switch item.metric {
            case .network: return "Network " + item.value.replacingOccurrences(of: "↓", with: "down ").replacingOccurrences(of: "↑", with: "up ")
            case .temperature: return "Temperature \(item.value)C"
            default: return "\(item.metric.title) \(item.value.trimmingCharacters(in: .whitespaces))"
            }
        }.joined(separator: ", ")
    }

    /// 0.07 → "  7%", 0.423 → " 42%", 1 → "100%".
    static func percent(_ fraction: Double?) -> String {
        guard let fraction, fraction.isFinite else { return "  –%" }
        let whole = Int((min(max(fraction, 0), 1) * 100).rounded())
        let text = "\(whole)%"
        return String(repeating: " ", count: max(0, 4 - text.count)) + text
    }

    /// Compact rates that stay at most five characters: "0K", "512K", "1.2M", "34M", "1.1G" (bytes per second, 1024-based).
    static func rate(_ bytesPerSecond: Double) -> String {
        let value = bytesPerSecond.isFinite ? max(bytesPerSecond, 0) : 0
        let kilo = value / 1024
        if kilo < 1000 { return "\(Int(kilo.rounded()))K" }
        let mega = kilo / 1024
        if mega < 10 { return String(format: "%.1fM", mega) }
        if mega < 1000 { return "\(Int(mega.rounded()))M" }
        return String(format: "%.1fG", mega / 1024)
    }

    static func level(_ value: Double?, warning: Double, critical: Double) -> ReadoutLevel {
        guard let value else { return .normal }
        return value >= critical ? .critical : value >= warning ? .warning : .normal
    }
}
