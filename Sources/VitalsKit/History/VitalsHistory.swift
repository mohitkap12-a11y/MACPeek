import Foundation
import MemoryPeekKit

/// One point of the history: the mean of the samples taken in its time slot (the worst pressure, the most swap).
public struct VitalsPoint: Equatable, Codable, Sendable {
    /// The start of the slot.
    public var time: Date
    /// How long the slot is: `VitalsHistory.fineSlot` for the last hour, `coarseSlot` before that.
    public var span: TimeInterval
    public var cpu: Double?
    public var memoryUsed: Double?
    public var pressure: MemoryPressure?
    public var swapUsedBytes: UInt64?
    public var networkIn: Double?
    public var networkOut: Double?
    public var gpu: Double?
    public var temperature: Double?
    public var power: Double?

    public init(time: Date, span: TimeInterval, cpu: Double? = nil, memoryUsed: Double? = nil, pressure: MemoryPressure? = nil,
                swapUsedBytes: UInt64? = nil, networkIn: Double? = nil, networkOut: Double? = nil, gpu: Double? = nil,
                temperature: Double? = nil, power: Double? = nil) {
        self.time = time
        self.span = span
        self.cpu = cpu
        self.memoryUsed = memoryUsed
        self.pressure = pressure
        self.swapUsedBytes = swapUsedBytes
        self.networkIn = networkIn
        self.networkOut = networkOut
        self.gpu = gpu
        self.temperature = temperature
        self.power = power
    }

    public func value(_ metric: VitalsMetric) -> Double? {
        switch metric {
        case .cpu: return cpu
        case .memory: return memoryUsed
        case .networkIn: return networkIn
        case .networkOut: return networkOut
        case .gpu: return gpu
        case .temperature: return temperature
        case .power: return power
        }
    }

    // Short keys: a day of points is written to disk every few minutes.
    private enum CodingKeys: String, CodingKey {
        case time = "t", span = "s", cpu = "c", memoryUsed = "m", pressure = "p", swapUsedBytes = "w", networkIn = "i",
             networkOut = "o", gpu = "g", temperature = "k", power = "e"
    }
}

/// A running mean that ignores missing readings.
struct Mean: Equatable, Codable, Sendable {
    var sum = 0.0
    var count = 0

    mutating func add(_ value: Double?) {
        guard let value, value.isFinite else { return }
        sum += value
        count += 1
    }

    var value: Double? { count > 0 ? sum / Double(count) : nil }
}

/// The last 24 hours of `VitalsSample`s, kept small: 10-second points for the last hour, one-minute points before that
/// (about 1,800 points in all). Samples are averaged into their slot as they arrive, so the monitor may sample as often
/// as it likes without the history growing.
public struct VitalsHistory: Equatable, Codable, Sendable {
    public static let fineSlot: TimeInterval = 10
    public static let coarseSlot: TimeInterval = 60
    /// Points younger than this keep their 10-second slots.
    public static let fineWindow: TimeInterval = 60 * 60
    public static let window: TimeInterval = 24 * 60 * 60
    /// Bumped when the stored format changes; a file with another version is discarded.
    public static let formatVersion = 1

    private struct Open: Equatable, Codable, Sendable {
        var slot: Date
        var cpu = Mean(), memory = Mean(), networkIn = Mean(), networkOut = Mean(), gpu = Mean(), temperature = Mean(), power = Mean()
        var pressure: MemoryPressure?
        var swap: UInt64?
    }

    public private(set) var points: [VitalsPoint] = []
    private var open: Open?
    private var version = VitalsHistory.formatVersion

    public init() {}

    public var isEmpty: Bool { points.isEmpty && open == nil }

    /// Adds a sample to its 10-second slot. A sample older than the open slot (the clock went back) starts afresh from
    /// that slot rather than rewriting the past.
    public mutating func record(_ sample: VitalsSample) {
        let slot = Self.start(of: sample.time, every: Self.fineSlot)
        if var current = open, current.slot == slot {
            Self.add(sample, to: &current)
            open = current
            return
        }
        closeOpenPoint()
        if let last = points.last, slot < last.time {
            points.removeAll { $0.time >= slot }
        }
        var fresh = Open(slot: slot)
        Self.add(sample, to: &fresh)
        open = fresh
    }

    /// Closes the open slot, merges points older than an hour into one-minute points and drops points older than a day.
    public mutating func prune(now: Date) {
        if let open, now.timeIntervalSince(open.slot) >= Self.fineSlot { closeOpenPoint() }
        let dayAgo = now.addingTimeInterval(-Self.window)
        points.removeAll { $0.time < dayAgo }
        let cutoff = Self.start(of: now.addingTimeInterval(-Self.fineWindow), every: Self.coarseSlot)
        var compacted: [VitalsPoint] = []
        var group: [VitalsPoint] = []
        var groupSlot: Date?
        func flush() {
            guard let slot = groupSlot, !group.isEmpty else { return }
            compacted.append(group.count == 1 && group[0].span == Self.coarseSlot ? group[0]
                             : Self.merge(group, time: slot, span: Self.coarseSlot))
            group = []
        }
        var recent: [VitalsPoint] = []
        for point in points {
            guard point.time < cutoff else {
                recent.append(point)
                continue
            }
            let slot = Self.start(of: point.time, every: Self.coarseSlot)
            if slot != groupSlot {
                flush()
                groupSlot = slot
            }
            group.append(point)
        }
        flush()
        points = compacted + recent
    }

    /// The points from `since` on, including the slot still open, merged evenly so there are at most `maximumCount`.
    public func points(since: Date, maximumCount: Int = 720) -> [VitalsPoint] {
        var all = points.filter { $0.time >= since }
        if let open, open.slot >= since { all.append(Self.point(from: open)) }
        guard maximumCount > 0, all.count > maximumCount else { return all }
        let size = Int((Double(all.count) / Double(maximumCount)).rounded(.up))
        return stride(from: 0, to: all.count, by: size).map { index in
            let group = Array(all[index..<min(index + size, all.count)])
            return Self.merge(group, time: group[0].time, span: group.reduce(0) { $0 + $1.span })
        }
    }

    public mutating func clear() {
        points = []
        open = nil
    }

    /// False for a history decoded from an older or newer format, which the caller should discard.
    public var isCurrentFormat: Bool { version == Self.formatVersion }

    // MARK: - Helpers

    private mutating func closeOpenPoint() {
        guard let open else { return }
        points.append(Self.point(from: open))
        self.open = nil
    }

    private static func add(_ sample: VitalsSample, to open: inout Open) {
        open.cpu.add(sample.cpu)
        open.memory.add(sample.memoryUsed)
        open.networkIn.add(sample.networkIn)
        open.networkOut.add(sample.networkOut)
        open.gpu.add(sample.gpu)
        open.temperature.add(sample.temperature)
        open.power.add(sample.power)
        open.pressure = worst(open.pressure, sample.pressure)
        if let swap = sample.swapUsedBytes { open.swap = max(open.swap ?? 0, swap) }
    }

    private static func point(from open: Open) -> VitalsPoint {
        VitalsPoint(time: open.slot, span: fineSlot, cpu: open.cpu.value, memoryUsed: open.memory.value, pressure: open.pressure,
                    swapUsedBytes: open.swap, networkIn: open.networkIn.value, networkOut: open.networkOut.value,
                    gpu: open.gpu.value, temperature: open.temperature.value, power: open.power.value)
    }

    /// The mean of a group of points, weighted by how long each covers.
    static func merge(_ group: [VitalsPoint], time: Date, span: TimeInterval) -> VitalsPoint {
        func mean(_ metric: VitalsMetric) -> Double? {
            var sum = 0.0, weight = 0.0
            for point in group {
                guard let value = point.value(metric) else { continue }
                sum += value * point.span
                weight += point.span
            }
            return weight > 0 ? sum / weight : nil
        }
        let pressure = group.reduce(nil as MemoryPressure?) { worst($0, $1.pressure) }
        let swap = group.compactMap(\.swapUsedBytes).max()
        return VitalsPoint(time: time, span: span, cpu: mean(.cpu), memoryUsed: mean(.memory), pressure: pressure,
                           swapUsedBytes: swap, networkIn: mean(.networkIn), networkOut: mean(.networkOut), gpu: mean(.gpu),
                           temperature: mean(.temperature), power: mean(.power))
    }

    static func worst(_ a: MemoryPressure?, _ b: MemoryPressure?) -> MemoryPressure? {
        func rank(_ p: MemoryPressure?) -> Int {
            switch p {
            case .critical: return 3
            case .warning: return 2
            case .normal: return 1
            case nil: return 0
            }
        }
        return rank(a) >= rank(b) ? a : b
    }

    static func start(of date: Date, every interval: TimeInterval) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / interval).rounded(.down) * interval)
    }
}

/// Reads and writes the history file. The file holds only numbers and times: no process names, nothing that leaves the
/// Mac unless a MacPeek Remote device of the Mac's own account asks for it.
public struct VitalsHistoryFile: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `~/Library/Application Support/MacPeek/vitals-history.json`.
    public static func standard() -> VitalsHistoryFile? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return VitalsHistoryFile(url: support.appendingPathComponent("MacPeek", isDirectory: true)
            .appendingPathComponent("vitals-history.json"))
    }

    /// An empty history when there is no file or it cannot be read.
    public func load(now: Date = Date()) -> VitalsHistory {
        guard let data = try? Data(contentsOf: url),
              var history = try? JSONDecoder.vitals.decode(VitalsHistory.self, from: data),
              history.isCurrentFormat else { return VitalsHistory() }
        history.prune(now: now)
        return history
    }

    public func save(_ history: VitalsHistory) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.vitals.encode(history).write(to: url, options: .atomic)
    }

    public func delete() {
        try? FileManager.default.removeItem(at: url)
    }
}

extension JSONEncoder {
    static var vitals: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }
}

extension JSONDecoder {
    static var vitals: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
