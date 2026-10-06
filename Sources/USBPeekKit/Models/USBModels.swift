import Foundation

/// One USB device as the I/O registry describes it. Serial numbers are deliberately not modelled at all:
/// the parser never reads them, so they cannot be displayed, copied or logged by accident.
public struct USBDevice: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let vendorName: String?
    public let vendorID: Int?
    public let productID: Int?
    /// Negotiated link speed in bits per second, when macOS reports it.
    public let linkSpeedBitsPerSecond: Double?
    /// The USB spec version in the device descriptor (bcdUSB), e.g. "3.20". It is what the device declares,
    /// not proof of the port or cable it is plugged into.
    public let declaredUSBVersion: String?
    public let deviceClass: Int?
    public let locationID: Int?
    public let children: [USBDevice]

    public init(id: String, name: String, vendorName: String? = nil, vendorID: Int? = nil, productID: Int? = nil,
                linkSpeedBitsPerSecond: Double? = nil, declaredUSBVersion: String? = nil, deviceClass: Int? = nil,
                locationID: Int? = nil, children: [USBDevice] = []) {
        self.id = id
        self.name = name
        self.vendorName = vendorName
        self.vendorID = vendorID
        self.productID = productID
        self.linkSpeedBitsPerSecond = linkSpeedBitsPerSecond
        self.declaredUSBVersion = declaredUSBVersion
        self.deviceClass = deviceClass
        self.locationID = locationID
        self.children = children
    }

    public var isHub: Bool { deviceClass == 9 }
    public var speedLabel: String? { linkSpeedBitsPerSecond.map(USBSpeed.label) }

    /// "0x05E3:0x0626", or nil when the registry gave neither id.
    public var vendorProductLabel: String? {
        guard let vendorID, let productID else { return nil }
        return String(format: "0x%04X:0x%04X", vendorID, productID)
    }

    public var deviceClassLabel: String? { deviceClass.map(USBClass.label) }

    /// This device and everything below it.
    public var flattened: [USBDevice] { [self] + children.flatMap(\.flattened) }

    /// Plain text for support threads. No serial number.
    public var copyText: String {
        var lines = ["Device: \(name)"]
        if let vendorName { lines.append("Vendor: \(vendorName)") }
        if let vendorProductLabel { lines.append("Vendor:product ID: \(vendorProductLabel)") }
        if let speedLabel { lines.append("Link speed: \(speedLabel)") }
        if let declaredUSBVersion { lines.append("Declared USB version: \(declaredUSBVersion)") }
        if let deviceClassLabel { lines.append("Device class: \(deviceClassLabel)") }
        return lines.joined(separator: "\n")
    }
}

/// A USB host controller and the devices attached below it.
public struct USBBus: Identifiable, Equatable, Sendable {
    public let id: String
    public let busNumber: Int?
    /// The registry class of the controller (for example `AppleT8112USBXHCI`), shown as secondary text.
    public let controllerClass: String
    public let devices: [USBDevice]

    public init(id: String, busNumber: Int?, controllerClass: String, devices: [USBDevice]) {
        self.id = id
        self.busNumber = busNumber
        self.controllerClass = controllerClass
        self.devices = devices
    }

    public var title: String { busNumber.map { "USB bus \($0)" } ?? "USB bus" }
    public var deviceCount: Int { devices.reduce(0) { $0 + $1.flattened.count } }
}

/// A Thunderbolt / USB4 receptacle as macOS reports it.
public struct ThunderboltPort: Identifiable, Equatable, Sendable {
    public let id: String
    public let busName: String
    public let receptacle: String?
    public let speed: String?
    public let status: String
    public let isConnected: Bool
    public let connectedDevices: [String]

    public init(id: String, busName: String, receptacle: String?, speed: String?, status: String,
                isConnected: Bool, connectedDevices: [String] = []) {
        self.id = id
        self.busName = busName
        self.receptacle = receptacle
        self.speed = speed
        self.status = status
        self.isConnected = isConnected
        self.connectedDevices = connectedDevices
    }
}

public struct USBSnapshot: Equatable, Sendable {
    public let buses: [USBBus]
    public let thunderboltPorts: [ThunderboltPort]
    /// Set when the Thunderbolt query failed or was unreadable; USB results are still valid.
    public let thunderboltNote: String?

    public init(buses: [USBBus], thunderboltPorts: [ThunderboltPort], thunderboltNote: String? = nil) {
        self.buses = buses
        self.thunderboltPorts = thunderboltPorts
        self.thunderboltNote = thunderboltNote
    }

    public var allDevices: [USBDevice] { buses.flatMap { $0.devices.flatMap(\.flattened) } }
    public var deviceCount: Int { allDevices.count }
}

public enum USBSpeed {
    /// 480_000_000 → "480 Mb/s"; 5_000_000_000 → "5 Gb/s"; 1_500_000 → "1.5 Mb/s".
    public static func label(_ bitsPerSecond: Double) -> String {
        func trimmed(_ value: Double) -> String { value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value) }
        if bitsPerSecond >= 1_000_000_000 { return "\(trimmed(bitsPerSecond / 1_000_000_000)) Gb/s" }
        return "\(trimmed(bitsPerSecond / 1_000_000)) Mb/s"
    }
}

public enum USBClass {
    public static func label(_ value: Int) -> String {
        switch value {
        case 0: return "Defined per interface"
        case 1: return "Audio"
        case 2: return "Communications"
        case 3: return "Human interface"
        case 7: return "Printer"
        case 8: return "Mass storage"
        case 9: return "Hub"
        case 14: return "Video"
        case 224: return "Wireless controller"
        case 239: return "Miscellaneous"
        case 255: return "Vendor specific"
        default: return "Class \(value)"
        }
    }
}
