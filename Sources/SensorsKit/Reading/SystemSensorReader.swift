import Foundation

#if os(macOS)
import IOKit

/// Reads temperatures, fans and power without administrator rights and without starting a process:
///
/// - **Temperatures, Apple silicon:** the HID event system's temperature services (`IOHIDEventSystemClient`), the
///   interface `powermetrics` and Activity Monitor's own tools use. It is not documented, so it is loaded at run time
///   and if anything is missing MacPeek simply shows no temperatures.
/// - **Temperatures, Intel:** well-known SMC keys (TC0P, TG0P, …).
/// - **Fans and power:** the System Management Controller (`AppleSMC`), read-only. Nothing is ever written to it.
public final class SystemSensorReader: SensorReading, @unchecked Sendable {
    private let lock = NSLock()
    private let isAppleSilicon: Bool
    private var smc: SMCConnection?
    private var smcTried = false
    private var hid: HIDTemperatureReader?
    private var hidTried = false
    /// The fan count and which Intel temperature keys exist are read once; they do not change while the Mac runs.
    private var fanCount: Int?
    private var intelTemperatureKeys: [String]?

    public init() {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        isAppleSilicon = sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
    }

    public func read() -> SensorSnapshot {
        lock.lock(); defer { lock.unlock() }
        if !smcTried {
            smcTried = true
            smc = SMCConnection()
        }
        var temperatures: [TemperatureSensor] = []
        if isAppleSilicon {
            if !hidTried {
                hidTried = true
                hid = HIDTemperatureReader()
            }
            temperatures = hid?.read() ?? []
        } else if let smc {
            temperatures = readIntelTemperatures(smc)
        }
        var fans: [FanReading] = []
        var watts: Double?
        if let smc {
            fans = readFans(smc)
            if let power = smc.value("PSTR"), power > 0, power < 1000 { watts = power }
        }
        var note: String?
        if temperatures.isEmpty && fans.isEmpty && watts == nil {
            note = "This Mac does not share its sensors with apps, or this version of macOS changed how they are read."
        }
        return SensorSnapshot(temperatures: temperatures.sorted { ($0.group.rawValue, $0.name) < ($1.group.rawValue, $1.name) },
                              fans: fans, systemWatts: watts, note: note)
    }

    private func readFans(_ smc: SMCConnection) -> [FanReading] {
        if fanCount == nil { fanCount = smc.value("FNum").map { min(max(Int($0), 0), 8) } ?? 0 }
        return (0..<(fanCount ?? 0)).compactMap { index in
            guard let rpm = smc.value("F\(index)Ac"), rpm >= 0, rpm < 20_000 else { return nil }
            return FanReading(index: index, rpm: rpm, minimumRPM: smc.value("F\(index)Mn"), maximumRPM: smc.value("F\(index)Mx"))
        }
    }

    /// Intel Macs: CPU proximity and die, GPU, memory, drive, battery and ambient keys, whichever this Mac has.
    static let intelKeys = ["TC0P", "TC0D", "TC0E", "TC0F", "TC1C", "TC2C", "TC3C", "TC4C", "TG0P", "TG0D", "TG1D", "TM0P",
                            "TH0P", "TB0T", "TB1T", "TA0P", "TPCD"]

    private func readIntelTemperatures(_ smc: SMCConnection) -> [TemperatureSensor] {
        if intelTemperatureKeys == nil {
            intelTemperatureKeys = Self.intelKeys.filter { smc.value($0).map(SensorClassifier.isPlausible) == true }
        }
        return (intelTemperatureKeys ?? []).compactMap { key in
            guard let celsius = smc.value(key), SensorClassifier.isPlausible(celsius) else { return nil }
            return TemperatureSensor(name: key, group: SensorClassifier.group(forSMCKey: key), celsius: celsius)
        }
    }
}

// MARK: - SMC

/// The structure `AppleSMC`'s user client exchanges (80 bytes). `padding` makes Swift lay it out as the C struct does:
/// the C compiler pads `keyInfo` to 12 bytes, Swift does not.
struct SMCParamStruct {
    struct Version {
        var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    struct PLimitData {
        var version: UInt16 = 0, length: UInt16 = 0
        var cpuPLimit: UInt32 = 0, gpuPLimit: UInt32 = 0, memPLimit: UInt32 = 0
    }

    struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var vers = Version()
    var pLimitData = PLimitData()
    var keyInfo = KeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
        (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

/// A read-only connection to the System Management Controller.
final class SMCConnection {
    private var connection: io_connect_t = 0
    private static let handleYPCEvent: UInt32 = 2
    private static let readKey: UInt8 = 5
    private static let getKeyInfo: UInt8 = 9

    init?() {
        guard MemoryLayout<SMCParamStruct>.stride == 80 else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else { return nil }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    /// The key's value as a number, or nil when the Mac has no such key or its type is not one MacPeek reads.
    func value(_ key: String) -> Double? {
        guard let raw = read(key) else { return nil }
        return SMCValue.decode(type: raw.type, bytes: raw.bytes)
    }

    func read(_ key: String) -> (type: String, bytes: [UInt8])? {
        var request = SMCParamStruct()
        request.key = SMCValue.code(key)
        request.data8 = Self.getKeyInfo
        guard let info = call(request), info.keyInfo.dataSize > 0 else { return nil }
        var read = SMCParamStruct()
        read.key = request.key
        read.keyInfo.dataSize = info.keyInfo.dataSize
        read.data8 = Self.readKey
        guard let answer = call(read) else { return nil }
        let size = Int(min(info.keyInfo.dataSize, 32))
        let bytes = withUnsafeBytes(of: answer.bytes) { Array($0.prefix(size)) }
        return (SMCValue.text(info.keyInfo.dataType), bytes)
    }

    private func call(_ input: SMCParamStruct) -> SMCParamStruct? {
        var input = input
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        let result = IOConnectCallStructMethod(connection, Self.handleYPCEvent, &input, MemoryLayout<SMCParamStruct>.stride,
                                               &output, &outputSize)
        guard result == kIOReturnSuccess, output.result == 0 else { return nil }
        return output
    }
}

// MARK: - HID temperature sensors (Apple silicon)

/// Apple silicon's temperature sensors, through the HID event system. Every function is looked up at run time.
final class HIDTemperatureReader {
    private typealias ClientCreate = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatching = @convention(c) (AnyObject, CFDictionary) -> Int32
    private typealias CopyServices = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyProperty = @convention(c) (AnyObject, CFString) -> Unmanaged<AnyObject>?
    private typealias CopyEvent = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias GetFloatValue = @convention(c) (AnyObject, Int32) -> Double

    private static let temperatureEvent: Int64 = 15
    private static let temperatureField: Int32 = 15 << 16

    private let client: AnyObject
    private let copyServices: CopyServices
    private let copyProperty: CopyProperty
    private let copyEvent: CopyEvent
    private let floatValue: GetFloatValue

    init?() {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else { return nil }
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: type)
        }
        guard let create = symbol("IOHIDEventSystemClientCreate", as: ClientCreate.self),
              let setMatching = symbol("IOHIDEventSystemClientSetMatching", as: SetMatching.self),
              let copyServices = symbol("IOHIDEventSystemClientCopyServices", as: CopyServices.self),
              let copyProperty = symbol("IOHIDServiceClientCopyProperty", as: CopyProperty.self),
              let copyEvent = symbol("IOHIDServiceClientCopyEvent", as: CopyEvent.self),
              let floatValue = symbol("IOHIDEventGetFloatValue", as: GetFloatValue.self),
              let client = create(kCFAllocatorDefault)?.takeRetainedValue() else { return nil }
        // Apple's vendor page, usage 5: temperature sensors.
        let matching = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary
        _ = setMatching(client, matching)
        self.client = client
        self.copyServices = copyServices
        self.copyProperty = copyProperty
        self.copyEvent = copyEvent
        self.floatValue = floatValue
    }

    func read() -> [TemperatureSensor] {
        guard let services = copyServices(client)?.takeRetainedValue() as? [AnyObject] else { return [] }
        var readings: [String: [Double]] = [:]
        for service in services {
            guard let name = copyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String,
                  let event = copyEvent(service, Self.temperatureEvent, 0, 0)?.takeRetainedValue() else { continue }
            let celsius = floatValue(event, Self.temperatureField)
            guard SensorClassifier.isPlausible(celsius) else { continue }
            readings[name, default: []].append(celsius)
        }
        // Several services can share a name; report each name once, at its mean.
        return readings.map { name, values in
            TemperatureSensor(name: name, group: SensorClassifier.group(forHIDName: name),
                              celsius: values.reduce(0, +) / Double(values.count))
        }
    }
}
#else
/// MacPeek ships for macOS only; elsewhere there are no sensors to read.
public final class SystemSensorReader: SensorReading, @unchecked Sendable {
    public init() {}
    public func read() -> SensorSnapshot { SensorSnapshot(temperatures: [], fans: [], note: "Sensors are read only on macOS.") }
}
#endif
