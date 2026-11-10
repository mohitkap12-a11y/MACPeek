import Foundation
import MacPeekCore

/// A Bluetooth device macOS knows, connected or paired. Its address is never read into the model.
public struct BluetoothDevice: Identifiable, Equatable, Codable, Sendable {
    public var id: String { name + (connected ? "#on" : "#off") }
    public let name: String
    public let connected: Bool
    /// macOS's word for the device type: "Headphones", "Keyboard", "Mouse"…
    public let kind: String?
    /// Battery levels in percent, as the device reports them through macOS. AirPods report left, right and case.
    public let batteryMain: Int?
    public let batteryLeft: Int?
    public let batteryRight: Int?
    public let batteryCase: Int?
    public let firmware: String?

    public init(name: String, connected: Bool, kind: String?, batteryMain: Int?, batteryLeft: Int?, batteryRight: Int?,
                batteryCase: Int?, firmware: String?) {
        self.name = name
        self.connected = connected
        self.kind = kind
        self.batteryMain = batteryMain
        self.batteryLeft = batteryLeft
        self.batteryRight = batteryRight
        self.batteryCase = batteryCase
        self.firmware = firmware
    }

    public var hasBattery: Bool { lowestBattery != nil }

    /// The lowest reported level, for sorting and warnings.
    public var lowestBattery: Int? { [batteryMain, batteryLeft, batteryRight].compactMap { $0 }.min() ?? batteryCase }

    /// "80%", or "L 100% · R 98% · Case 34%".
    public var batteryLabel: String? {
        var parts: [String] = []
        if let batteryMain { parts.append("\(batteryMain)%") }
        if let batteryLeft { parts.append("L \(batteryLeft)%") }
        if let batteryRight { parts.append("R \(batteryRight)%") }
        if let batteryCase { parts.append("Case \(batteryCase)%") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

public struct BluetoothReport: Equatable, Codable, Sendable {
    /// Whether Bluetooth is on, when macOS says.
    public let poweredOn: Bool?
    public let devices: [BluetoothDevice]

    public init(poweredOn: Bool?, devices: [BluetoothDevice]) {
        self.poweredOn = poweredOn
        self.devices = devices
    }

    /// Connected devices with no battery level from system_profiler (the I/O registry may know it).
    public var connectedWithoutBattery: [BluetoothDevice] { connected.filter { !$0.hasBattery } }

    /// The report with battery levels found elsewhere (the I/O registry, by product name) filled in for connected
    /// devices that system_profiler gave none for. Levels system_profiler did give are kept. A name two connected
    /// devices share is left alone: a level matched by name could belong to either.
    public func addingBatteries(_ levels: [String: Int]) -> BluetoothReport {
        guard !levels.isEmpty else { return self }
        var byName: [String: Int] = [:]
        for (name, level) in levels { byName[BluetoothReport.key(name)] = level }
        var connectedCount: [String: Int] = [:]
        for device in connected { connectedCount[BluetoothReport.key(device.name), default: 0] += 1 }
        return BluetoothReport(poweredOn: poweredOn, devices: devices.map { device in
            let key = BluetoothReport.key(device.name)
            guard device.connected, !device.hasBattery, connectedCount[key] == 1, let level = byName[key] else { return device }
            return BluetoothDevice(name: device.name, connected: true, kind: device.kind, batteryMain: level, batteryLeft: nil,
                                   batteryRight: nil, batteryCase: nil, firmware: device.firmware)
        })
    }

    /// Names compared without case or surrounding spaces, and with curly apostrophes made straight ("Mo’s Mouse").
    static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\u{2019}", with: "'").lowercased()
    }

    public var connected: [BluetoothDevice] { devices.filter(\.connected) }
    public var paired: [BluetoothDevice] { devices.filter { !$0.connected } }
    /// Connected devices at or below 20%.
    public var lowBattery: [BluetoothDevice] { connected.filter { ($0.lowestBattery ?? 100) <= 20 } }
}

/// `system_profiler SPBluetoothDataType -json` (macOS 12 and later): connected and not-connected devices, each a
/// one-key dictionary of name → properties.
public enum BluetoothParser {
    public static func parse(_ text: String) -> BluetoothReport? {
        guard let root = LooseJSON.parse(text) as? LooseJSON.Object,
              let sections = root["SPBluetoothDataType"] as? [Any] else { return nil }
        var powered: Bool?
        var devices: [BluetoothDevice] = []
        for case let section as LooseJSON.Object in sections {
            if let controller = LooseJSON.object(section, "controller_properties"),
               let state = LooseJSON.text(controller, "controller_state") {
                powered = state.lowercased().contains("on")
            }
            devices += list(section["device_connected"], connected: true)
            devices += list(section["device_not_connected"], connected: false)
        }
        return BluetoothReport(poweredOn: powered, devices: devices)
    }

    private static func list(_ value: Any?, connected: Bool) -> [BluetoothDevice] {
        (value as? [Any] ?? []).compactMap { $0 as? LooseJSON.Object }.flatMap { wrapper in
            wrapper.compactMap { name, properties -> BluetoothDevice? in
                guard let properties = properties as? LooseJSON.Object else { return nil }
                func battery(_ key: String) -> Int? { LooseJSON.text(properties, key).flatMap { ByteSizeText.percent($0) }.map { Int($0.rounded()) } }
                let left = battery("device_batteryLevelLeft"), right = battery("device_batteryLevelRight")
                let batteryCase = battery("device_batteryLevelCase")
                // Most devices say device_batteryLevelMain; some macOS versions and devices use another battery key.
                var main = battery("device_batteryLevelMain")
                if main == nil, left == nil, right == nil, batteryCase == nil {
                    main = properties.keys.sorted()
                        .filter { $0.hasPrefix("device_batteryLevel") || $0.hasPrefix("device_batteryPercent") }
                        .lazy.compactMap(battery).first
                }
                return BluetoothDevice(name: name, connected: connected, kind: LooseJSON.text(properties, "device_minorType"),
                                       batteryMain: main, batteryLeft: left, batteryRight: right, batteryCase: batteryCase,
                                       firmware: LooseJSON.text(properties, "device_firmwareVersion"))
            }
        }
    }
}

/// Battery levels from the I/O registry: `ioreg -r -a -k BatteryPercent` lists every registry entry that reports one
/// (Magic Keyboard, Mouse and Trackpad, and other Bluetooth accessories), as a property list. That is where macOS's own
/// Bluetooth menu reads them, and system_profiler leaves some of them out. Only the product name and the level are
/// read; addresses and serial numbers never enter the result.
public enum IORegBatteryParser {
    public static func parse(_ text: String) -> [String: Int] {
        guard let data = text.data(using: .utf8),
              let root = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else { return [:] }
        let entries = (root as? [Any]) ?? [root]
        var levels: [String: Int] = [:]
        var conflicting = Set<String>()
        for case let entry as [String: Any] in entries {
            guard let name = ["Product", "DeviceName", "Name"].lazy.compactMap({ entry[$0] as? String }).first?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
                  let level = percent(entry["BatteryPercent"]) else { continue }
            // One device appears once per HID interface, with the same level. Different levels under one name are
            // different devices, and a name cannot say which is which: that name is left out.
            if let known = levels[name], known != level { conflicting.insert(name) }
            levels[name] = level
        }
        for name in conflicting { levels[name] = nil }
        return levels
    }

    private static func percent(_ value: Any?) -> Int? {
        let number: Double?
        switch value {
        case let value as NSNumber: number = value.doubleValue
        case let value as String: number = ByteSizeText.percent(value)
        default: number = nil
        }
        guard let number, number.isFinite, (0...100).contains(number) else { return nil }
        return Int(number.rounded())
    }
}

public protocol BluetoothReading: Sendable {
    func bluetooth() async throws -> BluetoothReport
}

/// Reads `system_profiler SPBluetoothDataType -json`: no permission (it is not a Bluetooth connection, so macOS does
/// not ask for Bluetooth access). Device addresses are dropped by the parser. When a connected device has no battery
/// level there, the I/O registry is asked as well (`ioreg`, also read-only and without permission).
public struct SystemBluetoothReader: BluetoothReading {
    static let profiler = "/usr/sbin/system_profiler"
    static let ioreg = "/usr/sbin/ioreg"
    static let batteryArguments = ["-r", "-a", "-k", "BatteryPercent"]
    private let runner: CommandRunning

    public init(runner: CommandRunning = ShellCommand(timeout: 20)) {
        self.runner = runner
    }

    public func bluetooth() async throws -> BluetoothReport {
        let output = try await runner.run(Self.profiler, ["SPBluetoothDataType", "-json"])
        guard output.status == 0 else {
            let detail = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw USBError.commandFailed(detail.isEmpty ? "system_profiler exited with status \(output.status)" : detail)
        }
        guard let report = BluetoothParser.parse(output.stdout) else {
            throw USBError.commandFailed("macOS described Bluetooth in a format MacPeek does not understand.")
        }
        guard !report.connectedWithoutBattery.isEmpty else { return report }
        // Best effort: the devices are listed either way.
        guard let registry = try? await runner.run(Self.ioreg, Self.batteryArguments), registry.status == 0 else { return report }
        return report.addingBatteries(IORegBatteryParser.parse(registry.stdout))
    }
}
