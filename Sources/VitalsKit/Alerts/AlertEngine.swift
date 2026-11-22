import Foundation
import MemoryPeekKit
import CPUPeekKit
import MacPeekCore

/// What MacPeek warns about, and when. Every alert can be switched off on its own; the defaults are chosen so that a
/// healthy Mac never alerts.
public struct AlertSettings: Equatable, Codable, Sendable {
    /// A process using at least `runawayPercent` of one core…
    public var runawayEnabled = true
    public var runawayPercent: Double = 90
    /// …for this long without a break.
    public var runawayMinutes = 5

    /// A process whose memory footprint grew by at least `leakGrowthBytes` within `leakMinutes` and never shrank
    /// noticeably on the way: the shape of a leak.
    public var leakEnabled = true
    public var leakGrowthBytes: UInt64 = 2 << 30
    public var leakMinutes = 15

    /// Memory pressure critical (at once) or warning for `pressureWarningMinutes`.
    public var pressureEnabled = true
    public var pressureWarningMinutes = 10

    /// Swap use grew by at least `swapGrowthBytes` within `swapMinutes`.
    public var swapEnabled = true
    public var swapGrowthBytes: UInt64 = 2 << 30
    public var swapMinutes = 30

    /// Download + upload at or above `networkBytesPerSecond` for `networkMinutes`.
    public var networkEnabled = true
    public var networkBytesPerSecond: Double = 5_000_000
    public var networkMinutes = 5

    /// macOS reports a serious or critical thermal state (it is slowing the Mac to cool it down).
    public var thermalEnabled = true

    /// After an alert clears, the same alert is not sent again for this long.
    public var repeatMinutes = 60
    /// Process names never alerted about (the person chose "Don't alert about this app").
    public var ignoredProcesses: [String] = []

    public init() {}

    public static let `default` = AlertSettings()

    /// Decodes settings saved by an older MacPeek: keys it did not know keep their defaults.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let d = AlertSettings()
        runawayEnabled = try container.decodeIfPresent(Bool.self, forKey: .runawayEnabled) ?? d.runawayEnabled
        runawayPercent = try container.decodeIfPresent(Double.self, forKey: .runawayPercent) ?? d.runawayPercent
        runawayMinutes = try container.decodeIfPresent(Int.self, forKey: .runawayMinutes) ?? d.runawayMinutes
        leakEnabled = try container.decodeIfPresent(Bool.self, forKey: .leakEnabled) ?? d.leakEnabled
        leakGrowthBytes = try container.decodeIfPresent(UInt64.self, forKey: .leakGrowthBytes) ?? d.leakGrowthBytes
        leakMinutes = try container.decodeIfPresent(Int.self, forKey: .leakMinutes) ?? d.leakMinutes
        pressureEnabled = try container.decodeIfPresent(Bool.self, forKey: .pressureEnabled) ?? d.pressureEnabled
        pressureWarningMinutes = try container.decodeIfPresent(Int.self, forKey: .pressureWarningMinutes) ?? d.pressureWarningMinutes
        swapEnabled = try container.decodeIfPresent(Bool.self, forKey: .swapEnabled) ?? d.swapEnabled
        swapGrowthBytes = try container.decodeIfPresent(UInt64.self, forKey: .swapGrowthBytes) ?? d.swapGrowthBytes
        swapMinutes = try container.decodeIfPresent(Int.self, forKey: .swapMinutes) ?? d.swapMinutes
        networkEnabled = try container.decodeIfPresent(Bool.self, forKey: .networkEnabled) ?? d.networkEnabled
        networkBytesPerSecond = try container.decodeIfPresent(Double.self, forKey: .networkBytesPerSecond) ?? d.networkBytesPerSecond
        networkMinutes = try container.decodeIfPresent(Int.self, forKey: .networkMinutes) ?? d.networkMinutes
        thermalEnabled = try container.decodeIfPresent(Bool.self, forKey: .thermalEnabled) ?? d.thermalEnabled
        repeatMinutes = try container.decodeIfPresent(Int.self, forKey: .repeatMinutes) ?? d.repeatMinutes
        ignoredProcesses = try container.decodeIfPresent([String].self, forKey: .ignoredProcesses) ?? d.ignoredProcesses
    }

    /// True when any alert needs the per-process scan (runaway processes, memory growth).
    public var needsProcesses: Bool { runawayEnabled || leakEnabled }

    public func ignores(_ processName: String) -> Bool {
        ignoredProcesses.contains { $0.caseInsensitiveCompare(processName) == .orderedSame }
    }
}

/// One alert as it was raised. Process alerts name the process; the others describe the whole Mac.
public struct AlertEvent: Identifiable, Equatable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case runawayProcess, memoryGrowth, memoryPressure, swapGrowth, sustainedNetwork, thermal

        public var title: String {
            switch self {
            case .runawayProcess: return "Process stuck at high CPU"
            case .memoryGrowth: return "Process memory keeps growing"
            case .memoryPressure: return "Memory pressure"
            case .swapGrowth: return "Swap growing"
            case .sustainedNetwork: return "Sustained network traffic"
            case .thermal: return "Running hot"
            }
        }

        public var symbol: String {
            switch self {
            case .runawayProcess: return "cpu"
            case .memoryGrowth: return "chart.line.uptrend.xyaxis"
            case .memoryPressure: return "memorychip"
            case .swapGrowth: return "externaldrive"
            case .sustainedNetwork: return "arrow.up.arrow.down"
            case .thermal: return "thermometer.high"
            }
        }

        /// The utility that explains it.
        public var utilityID: String {
            switch self {
            case .runawayProcess, .thermal: return "cpupeek"
            case .memoryGrowth, .memoryPressure, .swapGrowth: return "memorypeek"
            case .sustainedNetwork: return "netpeek"
            }
        }
    }

    public let id: UUID
    public let kind: Kind
    public let time: Date
    public let title: String
    public let message: String
    public let pid: Int?
    public let processName: String?
    /// True for conditions people should act on soon (critical pressure, a critical thermal state).
    public let isCritical: Bool

    public init(id: UUID = UUID(), kind: Kind, time: Date, title: String, message: String, pid: Int? = nil,
                processName: String? = nil, isCritical: Bool = false) {
        self.id = id
        self.kind = kind
        self.time = time
        self.title = title
        self.message = message
        self.pid = pid
        self.processName = processName
        self.isCritical = isCritical
    }
}

/// One process as the monitor saw it: its CPU use over the last interval (percent of one core) and its footprint.
public struct ProcessObservation: Equatable, Sendable {
    public let pid: Int
    /// Which process holds the PID (its start time); a reused PID is a different process.
    public let generation: UInt64
    public let name: String
    public let cpuPercent: Double?
    public let footprintBytes: UInt64

    public init(pid: Int, generation: UInt64, name: String, cpuPercent: Double?, footprintBytes: UInt64) {
        self.pid = pid
        self.generation = generation
        self.name = name
        self.cpuPercent = cpuPercent
        self.footprintBytes = footprintBytes
    }
}

/// Everything the engine is told on one tick. `processes` is nil when the process scan did not run this tick, which is
/// not the same as an empty list.
public struct AlertObservation: Equatable, Sendable {
    public let time: Date
    public let processes: [ProcessObservation]?
    public let pressure: MemoryPressure?
    public let swapUsedBytes: UInt64?
    /// Download + upload over physical interfaces, bytes per second.
    public let networkBytesPerSecond: Double?
    public let thermal: ThermalLevel?

    public init(time: Date, processes: [ProcessObservation]? = nil, pressure: MemoryPressure? = nil, swapUsedBytes: UInt64? = nil,
                networkBytesPerSecond: Double? = nil, thermal: ThermalLevel? = nil) {
        self.time = time
        self.processes = processes
        self.pressure = pressure
        self.swapUsedBytes = swapUsedBytes
        self.networkBytesPerSecond = networkBytesPerSecond
        self.thermal = thermal
    }
}

/// Decides when to alert. It remembers when each condition started, raises one alert per episode (a condition that
/// stays true never alerts twice), and after it clears waits `repeatMinutes` before the same alert may be raised again.
public struct AlertEngine: Sendable {
    private struct ProcessKey: Hashable, Sendable {
        let pid: Int
        let generation: UInt64
    }

    /// When each condition (by key) became true.
    private var started: [String: Date] = [:]
    /// Conditions that already alerted in their current episode.
    private var raised: Set<String> = []
    /// When each key last alerted.
    private var lastRaised: [String: Date] = [:]
    /// Each process's footprint readings within the leak window, oldest first.
    private var footprints: [ProcessKey: [(time: Date, bytes: UInt64)]] = [:]
    /// Swap readings within the swap window, oldest first.
    private var swapReadings: [(time: Date, bytes: UInt64)] = []

    public init() {}

    public mutating func evaluate(_ observation: AlertObservation, settings: AlertSettings) -> [AlertEvent] {
        let now = observation.time
        var events: [AlertEvent] = []
        var stillTrue: Set<String> = []

        /// Records that `key` is true now and returns an alert when it has lasted `minutes` and may be raised.
        func condition(_ key: String, after minutes: Double, makeEvent: (Date) -> AlertEvent) {
            stillTrue.insert(key)
            let since = started[key] ?? now
            started[key] = since
            guard now.timeIntervalSince(since) >= minutes * 60, !raised.contains(key) else { return }
            if let last = lastRaised[key], now.timeIntervalSince(last) < Double(settings.repeatMinutes) * 60 { return }
            raised.insert(key)
            lastRaised[key] = now
            events.append(makeEvent(since))
        }

        if let processes = observation.processes {
            for trigger in processTriggers(processes, now: now, settings: settings) {
                condition(trigger.key, after: trigger.minutes, makeEvent: trigger.make)
            }
        } else {
            // No scan this tick: keep the process conditions as they are rather than clearing them.
            for key in started.keys where key.hasPrefix("cpu/") || key.hasPrefix("leak/") { stillTrue.insert(key) }
        }

        if settings.pressureEnabled, let pressure = observation.pressure {
            if pressure == .critical {
                condition("pressure/critical", after: 0) { _ in
                    AlertEvent(kind: .memoryPressure, time: now, title: "Memory pressure is critical",
                               message: "Your Mac is out of memory and is moving memory to disk. Quit apps you are not using.",
                               isCritical: true)
                }
            }
            if pressure != .normal {
                let minutes = settings.pressureWarningMinutes
                condition("pressure/warning", after: Double(minutes)) { _ in
                    AlertEvent(kind: .memoryPressure, time: now, title: "Memory pressure has been high for \(minutes) min",
                               message: "Your Mac is short of memory and has been compressing it or moving it to disk.")
                }
            }
        } else if observation.pressure == nil {
            for key in started.keys where key.hasPrefix("pressure/") { stillTrue.insert(key) }
        }

        if settings.swapEnabled, let swap = observation.swapUsedBytes {
            let window = Double(settings.swapMinutes) * 60
            swapReadings.append((now, swap))
            swapReadings.removeAll { now.timeIntervalSince($0.time) > window }
            if let lowest = swapReadings.map(\.bytes).min(), swap >= lowest, swap - lowest >= settings.swapGrowthBytes {
                let grown = swap - lowest
                condition("swap", after: 0) { _ in
                    AlertEvent(kind: .swapGrowth, time: now, title: "Swap grew by \(Self.bytes(grown))",
                               message: "In the last \(settings.swapMinutes) min your Mac moved \(Self.bytes(grown)) of memory to disk (\(Self.bytes(swap)) in total). Something is using more memory than the Mac has.")
                }
            }
        } else if !settings.swapEnabled {
            swapReadings = []
        }

        if settings.networkEnabled, let rate = observation.networkBytesPerSecond, rate >= settings.networkBytesPerSecond {
            let minutes = settings.networkMinutes
            condition("network", after: Double(minutes)) { _ in
                AlertEvent(kind: .sustainedNetwork, time: now, title: "Network busy for \(minutes) min",
                           message: "Your Mac has been sending and receiving \(ByteCountText.binary(rate))/s for \(minutes) min. NetPeek shows which interface.")
            }
        } else if observation.networkBytesPerSecond == nil {
            if started["network"] != nil { stillTrue.insert("network") }
        }

        if settings.thermalEnabled, let thermal = observation.thermal, thermal.isElevated {
            condition("thermal", after: 0) { _ in
                AlertEvent(kind: .thermal, time: now, title: "Your Mac is running hot",
                           message: thermal == .critical ? "macOS is slowing the CPU to cool it down." : "macOS may slow the CPU to cool it down.",
                           isCritical: thermal == .critical)
            }
        } else if observation.thermal == nil {
            if started["thermal"] != nil { stillTrue.insert("thermal") }
        }

        // Conditions that are no longer true end their episode.
        started = started.filter { stillTrue.contains($0.key) }
        raised = raised.filter { stillTrue.contains($0) }
        let forgetBefore = now.addingTimeInterval(-max(Double(settings.repeatMinutes) * 60, 60))
        lastRaised = lastRaised.filter { $0.value >= forgetBefore || stillTrue.contains($0.key) }
        return events
    }

    /// A process condition that is true on this tick; `evaluate` decides whether it alerts.
    private struct Trigger {
        let key: String
        let minutes: Double
        let make: (Date) -> AlertEvent
    }

    /// The process conditions true now. Also updates the footprint readings the memory-growth rule needs.
    private mutating func processTriggers(_ processes: [ProcessObservation], now: Date, settings: AlertSettings) -> [Trigger] {
        let leakWindow = Double(settings.leakMinutes) * 60
        var triggers: [Trigger] = []
        var seen: Set<ProcessKey> = []
        for process in processes where !settings.ignores(process.name) {
            let key = ProcessKey(pid: process.pid, generation: process.generation)
            seen.insert(key)
            let id = "\(process.pid)/\(process.generation)"

            if settings.runawayEnabled, let percent = process.cpuPercent, percent >= settings.runawayPercent {
                let minutes = settings.runawayMinutes
                triggers.append(Trigger(key: "cpu/" + id, minutes: Double(minutes)) { _ in
                    AlertEvent(kind: .runawayProcess, time: now,
                               title: "\(process.name) has used \(Int(percent.rounded()))% CPU for \(minutes) min",
                               message: "It may be stuck. CPUPeek shows it; ProcessPeek can quit it safely.",
                               pid: process.pid, processName: process.name)
                })
            }

            guard settings.leakEnabled else { continue }
            var readings = footprints[key] ?? []
            readings.append((now, process.footprintBytes))
            readings.removeAll { now.timeIntervalSince($0.time) > leakWindow }
            footprints[key] = readings
            // Only a (nearly) full window says anything: growth over 2 minutes is not a leak.
            guard let first = readings.first, now.timeIntervalSince(first.time) >= leakWindow * 0.8,
                  process.footprintBytes > first.bytes, process.footprintBytes - first.bytes >= settings.leakGrowthBytes,
                  Self.isSteadyGrowth(readings.map(\.bytes)) else { continue }
            let grown = process.footprintBytes - first.bytes
            let minutes = settings.leakMinutes
            triggers.append(Trigger(key: "leak/" + id, minutes: 0) { _ in
                AlertEvent(kind: .memoryGrowth, time: now,
                           title: "\(process.name) grew by \(Self.bytes(grown)) in \(minutes) min",
                           message: "It now uses \(Self.bytes(process.footprintBytes)) and has not given memory back. It may be leaking; restarting it frees the memory.",
                           pid: process.pid, processName: process.name)
            })
        }
        footprints = footprints.filter { seen.contains($0.key) }
        return triggers
    }

    /// True when the values mostly rise: no reading falls more than 10 % below the highest one before it.
    static func isSteadyGrowth(_ values: [UInt64]) -> Bool {
        var highest: UInt64 = 0
        for value in values {
            if Double(value) < Double(highest) * 0.9 { return false }
            highest = max(highest, value)
        }
        return true
    }

    static func bytes(_ count: UInt64) -> String { ByteCountText.memory(count) }
}
