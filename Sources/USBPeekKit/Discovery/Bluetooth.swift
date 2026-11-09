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
                return BluetoothDevice(name: name, connected: connected, kind: LooseJSON.text(properties, "device_minorType"),
                                       batteryMain: battery("device_batteryLevelMain"), batteryLeft: battery("device_batteryLevelLeft"),
                                       batteryRight: battery("device_batteryLevelRight"), batteryCase: battery("device_batteryLevelCase"),
                                       firmware: LooseJSON.text(properties, "device_firmwareVersion"))
            }
        }
    }
}

public protocol BluetoothReading: Sendable {
    func bluetooth() async throws -> BluetoothReport
}

/// Reads `system_profiler SPBluetoothDataType -json`: no permission (it is not a Bluetooth connection, so macOS does
/// not ask for Bluetooth access). Device addresses are dropped by the parser.
public struct SystemBluetoothReader: BluetoothReading {
    static let profiler = "/usr/sbin/system_profiler"
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
        return report
    }
}
