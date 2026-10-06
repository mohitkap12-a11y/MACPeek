#if os(macOS)
import Foundation
import DiskPeekKit

/// Observable state for DiskPeek. It samples per-process disk counters on a timer, but only while its screen is
/// on screen. Leaving the screen stops the timer and discards the baseline, so returning never shows a huge
/// "rate" computed over the time it was closed.
@MainActor
final class DiskStore: ObservableObject {
    @Published private(set) var activity: [DiskActivity] = []
    @Published private(set) var unreadableProcesses = 0
    @Published private(set) var isWaitingForSecondSample = true
    @Published private(set) var error: String?
    @Published var sort: DiskSort = .rate
    @Published private(set) var interval: TimeInterval = 2

    private let reader: DiskIOReading
    private let settings: AppSettings
    private var sampler = DiskIOSampler()
    private var pollTask: Task<Void, Never>?

    init(reader: DiskIOReading, settings: AppSettings) {
        self.reader = reader
        self.settings = settings
    }

    /// The rows to show, in the chosen order.
    var rows: [DiskActivity] { Array(DiskIOSampler.sorted(activity, by: sort).prefix(30)) }

    func startSampling() {
        stopSampling()
        sampler = DiskIOSampler()
        activity = []
        isWaitingForSecondSample = true
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                // Sampling faster than every 2 s only adds noise and cost.
                let seconds = max(self.settings.refreshInterval, 2)
                self.interval = seconds
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
        }
    }

    func stopSampling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func tick() async {
        let reader = self.reader
        do {
            // One libproc call per process: keep it off the main thread, and let leaving the screen stop a scan that
            // is already running (the reader polls the flag between processes).
            let flag = CancellationFlag()
            let result = try await withTaskCancellationHandler {
                try await Task.detached(priority: .utility) { try reader.read(isCancelled: { flag.isCancelled }) }.value
            } onCancel: {
                flag.cancel()
            }
            guard !Task.isCancelled else { return }
            let rows = sampler.ingest(result.counters, at: Date())
            activity = rows
            unreadableProcesses = result.unreadable
            isWaitingForSecondSample = sampler.isBaselineOnly
            error = nil
        } catch {
            if Task.isCancelled { return }
            // Do not leave the last good rates on screen as if they were current, and a gap invalidates the baseline.
            activity = []
            unreadableProcesses = 0
            sampler = DiskIOSampler()
            isWaitingForSecondSample = true
            self.error = error.localizedDescription
            Log.diskPeek.error("sampling failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
#endif
