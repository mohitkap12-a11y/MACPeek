#if canImport(CoreAudio)
import Foundation
import CoreAudio

/// Thin, synchronous wrappers over the Audio Hardware property API. Reading these properties never captures audio and
/// needs no permission; only starting I/O on an input device would.
enum CoreAudioProperty {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    static func address(_ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func has(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        return AudioObjectHasProperty(object, &address)
    }

    static func isSettable(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(object, &address, &settable) == noErr && settable.boolValue
    }

    /// A fixed-size property (UInt32, Float32, Float64, …), or nil when absent or unreadable.
    static func value<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, initial: T) -> T? {
        var address = address
        var result = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutableBytes(of: &result) { buffer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, buffer.baseAddress!)
        }
        return status == noErr ? result : nil
    }

    static func ids(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> [AudioObjectID]? {
        var address = address
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr else { return nil }
        let count = Int(size) / MemoryLayout<AudioObjectID>.stride
        guard count > 0 else { return [] }
        var result = [AudioObjectID](repeating: 0, count: count)
        var ioSize = size
        let status = result.withUnsafeMutableBytes { buffer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &ioSize, buffer.baseAddress!)
        }
        return status == noErr ? Array(result.prefix(Int(ioSize) / MemoryLayout<AudioObjectID>.stride)) : nil
    }

    static func string(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> String? {
        var address = address
        var reference: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &reference) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let reference else { return nil }
        return reference.takeRetainedValue() as String
    }

    /// Total channels across the device's streams in one direction; 0 when it has none, nil when not readable.
    static func channelCount(_ object: AudioObjectID, scope: AudioObjectPropertyScope) -> Int? {
        var streams = address(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &streams, 0, nil, &size) == noErr else { return nil }
        guard size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(object, &streams, 0, nil, &size, raw) == noErr else { return nil }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func controls(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> AudioControls {
        let muteAddress = address(kAudioDevicePropertyMute, scope: scope)
        var muted: Bool?
        var canSetMute = false
        if has(device, muteAddress), let raw: UInt32 = value(device, muteAddress, initial: 0) {
            muted = raw != 0
            canSetMute = isSettable(device, muteAddress)
        }
        return AudioControls(volume: volume(device, scope: scope), isMuted: muted, canSetMute: canSetMute)
    }

    /// The device's main volume, or the average of channels 1 and 2 for devices that only expose per-channel volume.
    private static func volume(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> Double? {
        let main = address(kAudioDevicePropertyVolumeScalar, scope: scope)
        if has(device, main), let v: Float32 = value(device, main, initial: 0) { return Double(v) }
        let channels: [Double] = [1, 2].compactMap { channel in
            let a = address(kAudioDevicePropertyVolumeScalar, scope: scope, element: AudioObjectPropertyElement(channel))
            guard has(device, a), let v: Float32 = value(device, a, initial: 0) else { return nil }
            return Double(v)
        }
        return channels.isEmpty ? nil : channels.reduce(0, +) / Double(channels.count)
    }

    static func scope(_ direction: AudioDirection) -> AudioObjectPropertyScope {
        direction == .input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput
    }
}

/// Core Audio (Audio Hardware) implementation of `AudioDeviceProviding`. Runs off the main thread (nonisolated async).
public struct CoreAudioDeviceProvider: AudioDeviceProviding {
    public init() {}

    public func snapshot() async throws -> AudioSnapshot {
        let system = CoreAudioProperty.system
        guard let ids = CoreAudioProperty.ids(system, CoreAudioProperty.address(kAudioHardwarePropertyDevices)) else {
            throw SoundPeekError.operationFailed("macOS did not return the list of audio devices.")
        }
        let devices = ids.compactMap { Self.device($0) }
        return AudioSnapshot(
            devices: devices,
            defaultInputID: Self.defaultDevice(kAudioHardwarePropertyDefaultInputDevice),
            defaultOutputID: Self.defaultDevice(kAudioHardwarePropertyDefaultOutputDevice))
    }

    public func setDefaultDevice(_ id: UInt32, direction: AudioDirection) async throws {
        let selector = direction == .input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice
        var address = CoreAudioProperty.address(selector)
        var device = AudioDeviceID(id)
        let status = AudioObjectSetPropertyData(CoreAudioProperty.system, &address, 0, nil,
                                                UInt32(MemoryLayout<AudioDeviceID>.size), &device)
        guard status == noErr else { throw SoundPeekError.operationFailed("macOS refused to change the default device (error \(status)).") }
    }

    public func setMuted(_ muted: Bool, deviceID: UInt32, direction: AudioDirection) async throws {
        var address = CoreAudioProperty.address(kAudioDevicePropertyMute, scope: CoreAudioProperty.scope(direction))
        var value: UInt32 = muted ? 1 : 0
        let status = AudioObjectSetPropertyData(AudioObjectID(deviceID), &address, 0, nil,
                                                UInt32(MemoryLayout<UInt32>.size), &value)
        guard status == noErr else { throw SoundPeekError.operationFailed("macOS refused to change mute (error \(status)).") }
    }

    private static func defaultDevice(_ selector: AudioObjectPropertySelector) -> UInt32? {
        let id: AudioObjectID? = CoreAudioProperty.value(CoreAudioProperty.system, CoreAudioProperty.address(selector), initial: 0)
        guard let id, id != AudioObjectID(kAudioObjectUnknown) else { return nil }
        return id
    }

    /// nil for hidden devices (not meant for users to choose).
    private static func device(_ id: AudioObjectID) -> AudioDevice? {
        let hidden: UInt32? = CoreAudioProperty.value(id, CoreAudioProperty.address(kAudioDevicePropertyIsHidden), initial: 0)
        if hidden == 1 { return nil }
        let name = CoreAudioProperty.string(id, CoreAudioProperty.address(kAudioObjectPropertyName)) ?? ""
        let transport: UInt32? = CoreAudioProperty.value(id, CoreAudioProperty.address(kAudioDevicePropertyTransportType), initial: 0)
        let rate: Float64? = CoreAudioProperty.value(id, CoreAudioProperty.address(kAudioDevicePropertyNominalSampleRate), initial: 0)
        let inputChannels = CoreAudioProperty.channelCount(id, scope: kAudioObjectPropertyScopeInput)
        let outputChannels = CoreAudioProperty.channelCount(id, scope: kAudioObjectPropertyScopeOutput)
        return AudioDevice(
            id: id, name: name, transport: AudioTransport.from(code: transport),
            inputChannels: inputChannels, outputChannels: outputChannels, sampleRate: rate,
            inputControls: (inputChannels ?? 0) > 0 ? CoreAudioProperty.controls(id, scope: kAudioObjectPropertyScopeInput) : .none,
            outputControls: (outputChannels ?? 0) > 0 ? CoreAudioProperty.controls(id, scope: kAudioObjectPropertyScopeOutput) : .none)
    }
}

/// Property listeners on the system object for the device list and both defaults. Registered only between `start` and
/// `stop`; the store starts it when SoundPeek appears and stops it when it disappears.
public final class CoreAudioChangeObserver: AudioChangeObserving, @unchecked Sendable {
    private struct Registration {
        var address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "app.macpeek.soundpeek.listener")
    private var registrations: [Registration] = []

    public init() {}

    deinit { stop() }

    public func start(_ handler: @escaping @Sendable () -> Void) {
        stop()
        lock.lock(); defer { lock.unlock() }
        let selectors = [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice,
                         kAudioHardwarePropertyDefaultOutputDevice]
        for selector in selectors {
            var address = CoreAudioProperty.address(selector)
            let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
            if AudioObjectAddPropertyListenerBlock(CoreAudioProperty.system, &address, queue, block) == noErr {
                registrations.append(Registration(address: address, block: block))
            }
        }
    }

    public func stop() {
        lock.lock(); defer { lock.unlock() }
        for var registration in registrations {
            AudioObjectRemovePropertyListenerBlock(CoreAudioProperty.system, &registration.address, queue, registration.block)
        }
        registrations.removeAll()
    }
}
#endif
