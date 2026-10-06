#if os(macOS)
import Foundation
import USBPeekKit

/// Observable state for USBPeek. Reads when the screen opens and then re-reads every few seconds while the screen is
/// visible, so plugging or unplugging a device shows up without reopening it. Leaving the screen stops everything.
@MainActor
final class USBStore: ObservableObject {
    @Published private(set) var snapshot: USBSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published var selectedID: String?

    private let discovery: USBDiscovering
    private let settings: AppSettings
    private var task: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    /// Every read gets a number; only the newest read may publish or clear the spinner, so overlapping poll and
    /// manual reads cannot overwrite each other.
    private var readGeneration = 0

    init(discovery: USBDiscovering, settings: AppSettings) {
        self.discovery = discovery
        self.settings = settings
    }

    /// Manual refresh (shows the spinner).
    func refresh() {
        task?.cancel()
        task = Task { [weak self] in await self?.load(showSpinner: true) }
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.load(showSpinner: self.snapshot == nil)
                let seconds = max(self.settings.refreshInterval, 3)
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        pollTask?.cancel()
        pollTask = nil
        isLoading = false
    }

    private func load(showSpinner: Bool) async {
        readGeneration += 1
        let generation = readGeneration
        if showSpinner { isLoading = true }
        defer { if !Task.isCancelled, generation == readGeneration { isLoading = false } }
        do {
            let result = try await discovery.snapshot()
            guard !Task.isCancelled, generation == readGeneration else { return }
            snapshot = result
            error = nil
            if let id = selectedID, !result.allDevices.contains(where: { $0.id == id }) { selectedID = nil }
        } catch {
            if Task.isCancelled || generation != readGeneration { return }
            self.error = error.localizedDescription
            Log.usbPeek.error("read failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
#endif
