#if os(macOS)
import Foundation
import SoundPeekKit

/// Observable state for SoundPeek. Core Audio is read off the main actor. Change listeners exist only while the screen is
/// visible, and a default-device change is only ever made by a button press (and can be undone).
@MainActor
final class SoundStore: ObservableObject {
    @Published private(set) var snapshot: AudioSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var banner: Banner?
    /// The last default-device change this session, for the Undo button.
    @Published private(set) var lastChange: DefaultDeviceChange?
    /// Volumes the user has dragged to but that Core Audio has not confirmed yet, so a slider doesn't jump back while a
    /// write or a refresh is in flight. Keyed by `volumeKey`.
    @Published private(set) var pendingVolumes: [String: Double] = [:]

    private let service: SoundPeekService
    private let observer: AudioChangeObserving
    /// What a finished action does to the saved Undo.
    private enum UndoUpdate: Sendable {
        case keep, clear
        case set(DefaultDeviceChange)
    }

    private var refreshTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var actionTask: Task<Void, Never>?
    private var volumeTasks: [String: Task<Void, Never>] = [:]

    init(service: SoundPeekService, observer: AudioChangeObserving) {
        self.service = service
        self.observer = observer
    }

    /// One-off read (launcher summary).
    func readOnce() async {
        do {
            let result = try await service.snapshot()
            guard !Task.isCancelled else { return }
            snapshot = result
            error = nil
            // Undo only makes sense while the default is still the one this app set; if it was changed elsewhere,
            // restoring the old device would override that newer choice.
            if let change = lastChange, result.defaultID(change.direction) != change.newID { lastChange = nil }
        } catch {
            if Task.isCancelled { return }
            self.error = error.localizedDescription
            Log.soundPeek.error("read failed")
        }
    }

    func start() {
        refresh()
        observer.start { [weak self] in
            Task { @MainActor [weak self] in self?.deviceChangeNotified() }
        }
    }

    func stop() {
        observer.stop()
        refreshTask?.cancel(); refreshTask = nil
        debounceTask?.cancel(); debounceTask = nil
        actionTask?.cancel(); actionTask = nil
        volumeTasks.values.forEach { $0.cancel() }
        volumeTasks.removeAll()
        pendingVolumes.removeAll()
        isLoading = false
    }

    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            self.isLoading = true
            defer { if !Task.isCancelled { self.isLoading = false } }
            await self.readOnce()
        }
    }

    /// Core Audio can fire several notifications for one plug event; wait briefly and read once.
    private func deviceChangeNotified() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    func setDefault(_ id: UInt32, direction: AudioDirection) {
        run { service in
            let (snapshot, change) = try await service.setDefault(id, direction: direction)
            return (snapshot, change.map(UndoUpdate.set) ?? .keep, change.map { _ in "\(direction.label) switched." })
        }
    }

    func undo() {
        guard let change = lastChange else { return }
        run { service in
            let snapshot = try await service.restore(change)
            return (snapshot, .clear, "Restored the previous \(change.direction.label.lowercased()) device.")
        }
    }

    func toggleMute(_ device: AudioDevice, direction: AudioDirection) {
        let muted = !(device.controls(direction).isMuted ?? false)
        run { service in
            let snapshot = try await service.setMuted(muted, deviceID: device.id, direction: direction)
            return (snapshot, .clear, muted ? "Muted." : "Unmuted.")
        }
    }

    static func volumeKey(_ device: AudioDevice, _ direction: AudioDirection) -> String {
        "\(device.id)-\(direction.rawValue)"
    }

    /// The volume to show: what the user just dragged to, else what the device reports.
    func displayedVolume(_ device: AudioDevice, direction: AudioDirection) -> Double {
        pendingVolumes[Self.volumeKey(device, direction)] ?? device.controls(direction).volume ?? 0
    }

    /// Called as the slider moves. Writes are debounced so a drag sends a handful of changes, not hundreds, and the last
    /// value always wins. Changing volume leaves the default-device Undo alone and shows no banner on success.
    func setVolume(_ value: Double, device: AudioDevice, direction: AudioDirection) {
        let value = min(max(value, 0), 1)
        let key = Self.volumeKey(device, direction)
        pendingVolumes[key] = value
        volumeTasks[key]?.cancel()
        let service = self.service
        volumeTasks[key] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            do {
                let snapshot = try await service.setVolume(value, deviceID: device.id, direction: direction)
                guard let self, !Task.isCancelled else { return }
                self.snapshot = snapshot
                self.error = nil
                if self.pendingVolumes[key] == value { self.pendingVolumes[key] = nil }
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.pendingVolumes[key] = nil
                self.banner = Banner(kind: .error, text: error.localizedDescription)
                Log.soundPeek.error("volume change failed")
                self.refresh()
            }
        }
    }

    private func run(_ operation: @escaping @Sendable (SoundPeekService) async throws -> (AudioSnapshot, UndoUpdate, String?)) {
        actionTask?.cancel()
        let service = self.service
        actionTask = Task { [weak self] in
            do {
                let (snapshot, undo, message) = try await operation(service)
                guard let self, !Task.isCancelled else { return }
                self.snapshot = snapshot
                self.error = nil
                // Undo is set by a default-device change, kept by a no-op, and cleared only once an undo or mute succeeded.
                switch undo {
                case .set(let change): self.lastChange = change
                case .clear: self.lastChange = nil
                case .keep: break
                }
                if let message { self.banner = Banner(kind: .success, text: message) }
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.banner = Banner(kind: .error, text: error.localizedDescription)
                Log.soundPeek.error("change failed")
                self.refresh()
            }
        }
    }

    func dismissBanner() { banner = nil }
}
#endif
