import Foundation

public enum AudioDirection: String, Sendable, CaseIterable {
    case input, output

    public var label: String { self == .input ? "Input" : "Output" }
}

/// How a device is connected, mapped from Core Audio's transport-type four-character codes.
/// `unknown` means macOS reported nothing; `other` is a code this version does not recognise (kept, never guessed at).
public enum AudioTransport: Equatable, Sendable {
    case builtIn, usb, bluetooth, bluetoothLE, hdmi, displayPort, airPlay, thunderbolt, firewire, pci
    case aggregate, virtual
    case other(UInt32)
    case unknown

    public static func fourCC(_ text: String) -> UInt32 {
        text.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    public static func from(code: UInt32?) -> AudioTransport {
        guard let code, code != 0 else { return .unknown }
        switch code {
        case fourCC("bltn"): return .builtIn
        case fourCC("usb "): return .usb
        case fourCC("blue"): return .bluetooth
        case fourCC("blea"): return .bluetoothLE
        case fourCC("hdmi"): return .hdmi
        case fourCC("dprt"): return .displayPort
        case fourCC("airp"): return .airPlay
        case fourCC("thun"): return .thunderbolt
        case fourCC("1394"): return .firewire
        case fourCC("pci "): return .pci
        case fourCC("grup"), fourCC("auto"): return .aggregate
        case fourCC("virt"): return .virtual
        default: return .other(code)
        }
    }

    public var label: String {
        switch self {
        case .builtIn: return "Built-in"
        case .usb: return "USB"
        case .bluetooth: return "Bluetooth"
        case .bluetoothLE: return "Bluetooth LE"
        case .hdmi: return "HDMI"
        case .displayPort: return "DisplayPort"
        case .airPlay: return "AirPlay"
        case .thunderbolt: return "Thunderbolt"
        case .firewire: return "FireWire"
        case .pci: return "PCI"
        case .aggregate: return "Aggregate device"
        case .virtual: return "Virtual"
        case .other: return "Other"
        case .unknown: return "Not reported"
        }
    }
}

/// What a device exposes for one direction. Every field is optional: macOS devices vary, and a missing property is
/// shown as unavailable rather than invented.
public struct AudioControls: Equatable, Sendable {
    /// 0...1, only when the device exposes a readable volume.
    public let volume: Double?
    public let isMuted: Bool?
    /// Whether the mute property can be written. Never true when `isMuted` is nil.
    public let canSetMute: Bool
    /// Whether the volume can be written. Never true when `volume` is nil.
    public let canSetVolume: Bool

    public init(volume: Double? = nil, isMuted: Bool? = nil, canSetMute: Bool = false, canSetVolume: Bool = false) {
        self.volume = volume.map { min(max($0, 0), 1) }
        self.isMuted = isMuted
        self.canSetMute = isMuted != nil && canSetMute
        self.canSetVolume = volume != nil && canSetVolume
    }

    public static let none = AudioControls()

    public var volumeLabel: String? {
        guard let volume else { return nil }
        return "\(Int((volume * 100).rounded()))%"
    }
}

/// One audio device as Core Audio reported it at a moment in time.
/// `id` is a runtime identifier only: it can change when a device reconnects or after a restart.
public struct AudioDevice: Identifiable, Equatable, Sendable {
    public let id: UInt32
    public let name: String
    public let transport: AudioTransport
    /// nil = not reported; 0 = the device has no streams in that direction.
    public let inputChannels: Int?
    public let outputChannels: Int?
    public let sampleRate: Double?
    public let inputControls: AudioControls
    public let outputControls: AudioControls

    public init(id: UInt32, name: String, transport: AudioTransport = .unknown,
                inputChannels: Int? = nil, outputChannels: Int? = nil, sampleRate: Double? = nil,
                inputControls: AudioControls = .none, outputControls: AudioControls = .none) {
        self.id = id
        self.name = name.isEmpty ? "Unnamed device" : name
        self.transport = transport
        self.inputChannels = inputChannels
        self.outputChannels = outputChannels
        self.sampleRate = sampleRate
        self.inputControls = inputControls
        self.outputControls = outputControls
    }

    public var hasInput: Bool { (inputChannels ?? 0) > 0 }
    public var hasOutput: Bool { (outputChannels ?? 0) > 0 }
    public var isBuiltIn: Bool { transport == .builtIn }

    public func supports(_ direction: AudioDirection) -> Bool {
        direction == .input ? hasInput : hasOutput
    }

    public func channels(_ direction: AudioDirection) -> Int? {
        direction == .input ? inputChannels : outputChannels
    }

    public func controls(_ direction: AudioDirection) -> AudioControls {
        direction == .input ? inputControls : outputControls
    }

    /// "48 kHz", "44.1 kHz".
    public var sampleRateLabel: String? {
        guard let sampleRate, sampleRate > 0 else { return nil }
        return String(format: "%g kHz", sampleRate / 1000)
    }

    /// "2 channels (stereo)" style label for one direction, nil when the device did not report it.
    public func channelLabel(_ direction: AudioDirection) -> String? {
        guard let count = channels(direction), count > 0 else { return nil }
        if count == 2 { return "Stereo" }
        return count == 1 ? "1 channel" : "\(count) channels"
    }

    /// "48 kHz · Stereo", or whichever parts macOS reported.
    public func formatLabel(_ direction: AudioDirection) -> String? {
        let parts = [sampleRateLabel, channelLabel(direction)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Everything SoundPeek knows at one moment.
public struct AudioSnapshot: Equatable, Sendable {
    public let devices: [AudioDevice]
    public let defaultInputID: UInt32?
    public let defaultOutputID: UInt32?
    public let updatedAt: Date

    public init(devices: [AudioDevice], defaultInputID: UInt32?, defaultOutputID: UInt32?, updatedAt: Date = Date()) {
        self.devices = devices
        self.defaultInputID = defaultInputID
        self.defaultOutputID = defaultOutputID
        self.updatedAt = updatedAt
    }

    public func device(_ id: UInt32) -> AudioDevice? { devices.first { $0.id == id } }

    public func defaultID(_ direction: AudioDirection) -> UInt32? {
        direction == .input ? defaultInputID : defaultOutputID
    }

    public func defaultDevice(_ direction: AudioDirection) -> AudioDevice? {
        defaultID(direction).flatMap(device)
    }

    /// Devices that can do `direction`: default first, then built-in, then by name, so the order is stable between refreshes.
    public func devices(for direction: AudioDirection) -> [AudioDevice] {
        let defaultID = self.defaultID(direction)
        return devices.filter { $0.supports(direction) }.sorted { a, b in
            if (a.id == defaultID) != (b.id == defaultID) { return a.id == defaultID }
            if a.isBuiltIn != b.isBuiltIn { return a.isBuiltIn }
            let order = a.name.localizedCaseInsensitiveCompare(b.name)
            return order == .orderedSame ? a.id < b.id : order == .orderedAscending
        }
    }

    /// Devices whose direction macOS did not report at all.
    public var devicesWithoutDirection: [AudioDevice] {
        devices.filter { !$0.hasInput && !$0.hasOutput }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Names for display, made unique: two devices called "USB Audio" are told apart by connection, then by number.
    public func displayNames() -> [UInt32: String] {
        var names: [UInt32: String] = [:]
        let groups = Dictionary(grouping: devices, by: { $0.name })
        for (name, group) in groups {
            guard group.count > 1 else { names[group[0].id] = name; continue }
            let sorted = group.sorted { $0.id < $1.id }
            let transports = Set(sorted.map { $0.transport.label })
            for (index, device) in sorted.enumerated() {
                names[device.id] = transports.count == sorted.count
                    ? "\(name) (\(device.transport.label))"
                    : "\(name) (\(index + 1))"
            }
        }
        return names
    }

    /// Plain-text report for support threads. No device IDs, UIDs or serial numbers.
    public func diagnosticReport(macOSVersion: String? = nil) -> String {
        let names = displayNames()
        func line(_ device: AudioDevice, _ direction: AudioDirection) -> String {
            var parts = [names[device.id] ?? device.name, device.transport.label]
            if let format = device.formatLabel(direction) { parts.append(format) }
            let controls = device.controls(direction)
            if let volume = controls.volumeLabel { parts.append("volume \(volume)") }
            if let muted = controls.isMuted { parts.append(muted ? "muted" : "not muted") }
            if device.id == defaultID(direction) { parts.append("default") }
            return "  - " + parts.joined(separator: ", ")
        }
        var lines = ["SoundPeek report"]
        if let macOSVersion { lines.append("macOS: \(macOSVersion)") }
        for direction in AudioDirection.allCases.reversed() {
            let list = devices(for: direction)
            lines.append("\(direction.label) devices (\(list.count)):")
            lines.append(contentsOf: list.map { line($0, direction) })
        }
        return lines.joined(separator: "\n")
    }
}

/// A default-device change the user made, kept so it can be undone.
public struct DefaultDeviceChange: Equatable, Sendable {
    public let direction: AudioDirection
    public let previousID: UInt32?
    public let newID: UInt32
    public init(direction: AudioDirection, previousID: UInt32?, newID: UInt32) {
        self.direction = direction
        self.previousID = previousID
        self.newID = newID
    }
}

public enum SoundPeekError: Error, LocalizedError, Equatable {
    case deviceUnavailable
    case notSupported(String)
    case operationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .deviceUnavailable: return "That audio device is no longer available."
        case .notSupported(let detail): return detail
        case .operationFailed(let detail): return detail
        }
    }
}
