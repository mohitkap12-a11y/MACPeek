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

    private let service: SoundPeekService
    private let observer: AudioChangeObserving
    private var refreshTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var actionTask: Task<Void, Never>?

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
            return (snapshot, change, change.map { _ in "\(direction.label) switched." })
        }
    }

    func undo() {
        guard let change = lastChange else { return }
        run { service in
            let snapshot = try await service.restore(change)
            return (snapshot, nil, "Restored the previous \(change.direction.label.lowercased()) device.")
        }
        lastChange = nil
    }

    func toggleMute(_ device: AudioDevice, direction: AudioDirection) {
        let muted = !(device.controls(direction).isMuted ?? false)
        run { service in
            let snapshot = try await service.setMuted(muted, deviceID: device.id, direction: direction)
            return (snapshot, nil, muted ? "Muted." : "Unmuted.")
        }
    }

    private func run(_ operation: @escaping @Sendable (SoundPeekService) async throws -> (AudioSnapshot, DefaultDeviceChange?, String?)) {
        actionTask?.cancel()
        let service = self.service
        actionTask = Task { [weak self] in
            do {
                let (snapshot, change, message) = try await operation(service)
                guard let self, !Task.isCancelled else { return }
                self.snapshot = snapshot
                self.error = nil
                // Undo is offered only right after a default-device change, never after a later mute or refresh.
                self.lastChange = change
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
