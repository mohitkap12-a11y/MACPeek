import Foundation
import MacPeekCore
#if canImport(Darwin)
import Darwin
#endif

public enum GPUError: Error, Equatable, LocalizedError {
    case commandFailed(String)
    case unreadable

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let detail): return detail
        case .unreadable: return "macOS described its GPUs in a format MacPeek does not understand."
        }
    }
}

/// Energy counters over the time since the previous call. Nil on the first call.
public protocol PowerSampling: Sendable {
    /// Why power cannot be read on this Mac, or nil when it can.
    var unavailableReason: String? { get }
    func sample() -> PowerReading?
}

public protocol GPUReading: Sendable {
    /// Reads the GPUs and their clients. `previous` (the clients of the last reading) and `interval` turn GPU time into
    /// per-process shares; the returned clients are the ones to pass next time.
    func snapshot(previousClients: [GPUClient]?, interval: TimeInterval) async throws -> (GPUSnapshot, [GPUClient])
    /// Only the clients (for ModelPeek, which needs per-process GPU time but not the rest).
    func clients() async throws -> [GPUClient]
}

/// Reads `ioreg -r -d 2 -c IOAccelerator -a -w0` (read-only, no permission) and, on Apple silicon, the power counters.
public struct SystemGPUReader: GPUReading {
    static let ioreg = "/usr/sbin/ioreg"
    static let arguments = ["-r", "-d", "2", "-c", "IOAccelerator", "-a", "-w0"]
    private let runner: CommandRunning
    private let power: PowerSampling?
    private let hasNeuralEngine: Bool

    public init(runner: CommandRunning = ShellCommand(timeout: 10), power: PowerSampling? = nil,
                hasNeuralEngine: Bool = SystemGPUReader.isAppleSilicon) {
        self.runner = runner
        self.power = power
        self.hasNeuralEngine = hasNeuralEngine
    }

    private func read() async throws -> IORegGPUParser.Result {
        let output = try await runner.run(Self.ioreg, Self.arguments)
        guard output.status == 0 else {
            let detail = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw GPUError.commandFailed(detail.isEmpty ? "ioreg exited with status \(output.status)" : detail)
        }
        if output.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return IORegGPUParser.Result(gpus: [], clients: [])
        }
        guard let result = IORegGPUParser.parse(output.stdout) else { throw GPUError.unreadable }
        return result
    }

    public func snapshot(previousClients: [GPUClient]?, interval: TimeInterval) async throws -> (GPUSnapshot, [GPUClient]) {
        let result = try await read()
        let processes = GPUClientSampling.usage(current: result.clients, previous: previousClients, interval: interval)
        let reading = power?.sample()
        let note: String?
        if let power { note = power.unavailableReason } else { note = "Power counters are not read on this Mac." }
        return (GPUSnapshot(gpus: result.gpus, processes: processes, power: reading, powerNote: reading == nil ? note : nil,
                            hasNeuralEngine: hasNeuralEngine), result.clients)
    }

    public func clients() async throws -> [GPUClient] { try await read().clients }

    /// Every Apple silicon Mac has a Neural Engine; Intel Macs have none.
    public static var isAppleSilicon: Bool {
        #if canImport(Darwin)
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
        #else
        return false
        #endif
    }
}

#if canImport(Darwin) && canImport(CoreFoundation)
import CoreFoundation

/// Power from IOReport's `Energy Model` channels, the counters `powermetrics` reads, without administrator rights.
///
/// IOReport is not a public framework: it is loaded at run time from `/usr/lib/libIOReport.dylib`, and if it or any
/// function is missing this sampler simply reports that power is unavailable. Nothing is written and no permission is
/// asked for. Only the `Energy Model` group is subscribed to.
public final class IOReportPowerSampler: PowerSampling, @unchecked Sendable {
    private typealias CopyChannelsInGroup = @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFDictionary>?
    private typealias CreateSubscription = @convention(c) (UnsafeMutableRawPointer?, CFMutableDictionary,
                                                          UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>?, UInt64,
                                                          CFTypeRef?) -> OpaquePointer?
    private typealias CreateSamples = @convention(c) (OpaquePointer, CFMutableDictionary?, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias CreateSamplesDelta = @convention(c) (CFDictionary, CFDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias ChannelString = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    private typealias SimpleIntegerValue = @convention(c) (CFDictionary, Int32) -> Int64

    private let lock = NSLock()
    private var subscription: OpaquePointer?
    private var subscribed: CFMutableDictionary?
    private var createSamples: CreateSamples?
    private var createDelta: CreateSamplesDelta?
    private var channelName: ChannelString?
    private var unitLabel: ChannelString?
    private var integerValue: SimpleIntegerValue?
    private var last: (sample: CFDictionary, time: Date)?
    public private(set) var unavailableReason: String?

    public init() {
        guard SystemGPUReader.isAppleSilicon else {
            unavailableReason = "Power counters are only read on Apple silicon Macs."
            return
        }
        guard let handle = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW) else {
            unavailableReason = "macOS's energy counters are not available on this version of macOS."
            return
        }
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: type)
        }
        guard let copyChannels = symbol("IOReportCopyChannelsInGroup", as: CopyChannelsInGroup.self),
              let subscribe = symbol("IOReportCreateSubscription", as: CreateSubscription.self),
              let samples = symbol("IOReportCreateSamples", as: CreateSamples.self),
              let delta = symbol("IOReportCreateSamplesDelta", as: CreateSamplesDelta.self),
              let name = symbol("IOReportChannelGetChannelName", as: ChannelString.self),
              let unit = symbol("IOReportChannelGetUnitLabel", as: ChannelString.self),
              let integer = symbol("IOReportSimpleGetIntegerValue", as: SimpleIntegerValue.self) else {
            unavailableReason = "macOS's energy counters are not available on this version of macOS."
            return
        }
        guard let channels = copyChannels("Energy Model" as CFString, nil, 0, 0, 0)?.takeRetainedValue(),
              let mutable = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, channels) else {
            unavailableReason = "macOS did not list any energy counters."
            return
        }
        var subscribedChannels: Unmanaged<CFMutableDictionary>?
        guard let sub = subscribe(nil, mutable, &subscribedChannels, 0, nil) else {
            unavailableReason = "macOS refused to share its energy counters."
            return
        }
        subscription = sub
        subscribed = subscribedChannels?.takeRetainedValue()
        createSamples = samples
        createDelta = delta
        channelName = name
        unitLabel = unit
        integerValue = integer
    }

    public func sample() -> PowerReading? {
        lock.lock(); defer { lock.unlock() }
        guard let subscription, let createSamples, let createDelta, let channelName, let unitLabel, let integerValue,
              let current = createSamples(subscription, subscribed, nil)?.takeRetainedValue() else { return nil }
        let now = Date()
        defer { last = (current, now) }
        guard let last, let delta = createDelta(last.sample, current, nil)?.takeRetainedValue() else { return nil }
        let interval = now.timeIntervalSince(last.time)
        guard let array = (delta as NSDictionary)["IOReportChannels"] as? [Any] else { return nil }
        var channels: [(name: String, value: Int64, unit: String)] = []
        for item in array {
            guard let dictionary = item as? NSDictionary else { continue }
            let channel = dictionary as CFDictionary
            guard let name = channelName(channel).map({ $0.takeUnretainedValue() as String }) else { continue }
            let unit = unitLabel(channel).map { $0.takeUnretainedValue() as String } ?? ""
            channels.append((name, integerValue(channel, 0), unit))
        }
        return EnergyMath.reading(channels: channels, interval: interval)
    }
}
#endif
