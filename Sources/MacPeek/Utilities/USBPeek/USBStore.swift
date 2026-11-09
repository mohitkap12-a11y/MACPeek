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
    /// Bluetooth devices and their batteries: read once per visit and on manual refresh (system_profiler is slow).
    @Published private(set) var bluetooth: BluetoothReport?
    @Published private(set) var bluetoothError: String?

    private let discovery: USBDiscovering
    private let bluetoothReader: BluetoothReading?
    private var bluetoothTask: Task<Void, Never>?
    private let settings: AppSettings
    private var task: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    /// Every read gets a number; only the newest read may publish or clear the spinner, so overlapping poll and
    /// manual reads cannot overwrite each other.
    private var readGeneration = 0

    init(discovery: USBDiscovering, bluetooth: BluetoothReading? = nil, settings: AppSettings) {
        self.discovery = discovery
        self.bluetoothReader = bluetooth
        self.settings = settings
    }

    func reloadBluetooth() {
        guard let bluetoothReader else { return }
        bluetoothTask?.cancel()
        bluetoothTask = Task { [weak self] in
            do {
                let report = try await bluetoothReader.bluetooth()
                guard !Task.isCancelled else { return }
                self?.bluetooth = report
                self?.bluetoothError = nil
            } catch {
                if Task.isCancelled { return }
                self?.bluetoothError = error.localizedDescription
                Log.usbPeek.error("bluetooth failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Manual refresh (shows the spinner).
    func refresh() {
        reloadBluetooth()
        task?.cancel()
        task = Task { [weak self] in await self?.load(showSpinner: true) }
    }

    func startPolling() {
        reloadBluetooth()
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
        bluetoothTask?.cancel()
        bluetoothTask = nil
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
