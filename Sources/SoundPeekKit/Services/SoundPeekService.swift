import Foundation

/// Reads and (for supported properties only) changes audio devices. The Core Audio implementation is the only code
/// that talks to the audio hardware API; everything else works against this protocol.
public protocol AudioDeviceProviding: Sendable {
    func snapshot() async throws -> AudioSnapshot
    func setDefaultDevice(_ id: UInt32, direction: AudioDirection) async throws
    func setMuted(_ muted: Bool, deviceID: UInt32, direction: AudioDirection) async throws
    /// `volume` is 0...1 and has already been clamped by the service.
    func setVolume(_ volume: Double, deviceID: UInt32, direction: AudioDirection) async throws
}

/// Reports when the device list or a default device changes. Listeners are only registered between `start` and `stop`.
public protocol AudioChangeObserving: AnyObject, Sendable {
    func start(_ handler: @escaping @Sendable () -> Void)
    func stop()
}

/// Validates every user-initiated change against a fresh snapshot, so a device that was unplugged, or one that cannot do
/// what was asked, is refused instead of being sent to Core Audio.
public struct SoundPeekService: Sendable {
    private let provider: AudioDeviceProviding

    public init(provider: AudioDeviceProviding) {
        self.provider = provider
    }

    public func snapshot() async throws -> AudioSnapshot { try await provider.snapshot() }

    /// Makes `id` the default for `direction`. Returns the new snapshot and what changed (nil if it already was the default).
    public func setDefault(_ id: UInt32, direction: AudioDirection) async throws -> (AudioSnapshot, DefaultDeviceChange?) {
        let before = try await provider.snapshot()
        guard let device = before.device(id) else { throw SoundPeekError.deviceUnavailable }
        guard device.supports(direction) else {
            throw SoundPeekError.notSupported("\(device.name) does not report an \(direction.label.lowercased()) stream.")
        }
        if before.defaultID(direction) == id { return (before, nil) }
        try await provider.setDefaultDevice(id, direction: direction)
        let after = try await provider.snapshot()
        return (after, DefaultDeviceChange(direction: direction, previousID: before.defaultID(direction), newID: id))
    }

    /// Puts the previous default back, if that device is still connected.
    public func restore(_ change: DefaultDeviceChange) async throws -> AudioSnapshot {
        guard let previous = change.previousID else { throw SoundPeekError.deviceUnavailable }
        return try await setDefault(previous, direction: change.direction).0
    }

    public func setMuted(_ muted: Bool, deviceID: UInt32, direction: AudioDirection) async throws -> AudioSnapshot {
        let before = try await provider.snapshot()
        guard let device = before.device(deviceID) else { throw SoundPeekError.deviceUnavailable }
        guard device.controls(direction).canSetMute else {
            throw SoundPeekError.notSupported("\(device.name) does not allow mute to be changed.")
        }
        try await provider.setMuted(muted, deviceID: deviceID, direction: direction)
        return try await provider.snapshot()
    }

    /// Sets the device's volume (clamped to 0...1) only when it reports a writable one. Does not change mute.
    public func setVolume(_ volume: Double, deviceID: UInt32, direction: AudioDirection) async throws -> AudioSnapshot {
        let before = try await provider.snapshot()
        guard let device = before.device(deviceID) else { throw SoundPeekError.deviceUnavailable }
        guard device.controls(direction).canSetVolume else {
            throw SoundPeekError.notSupported("\(device.name) does not allow its volume to be changed.")
        }
        try await provider.setVolume(min(max(volume, 0), 1), deviceID: deviceID, direction: direction)
        return try await provider.snapshot()
    }
}
