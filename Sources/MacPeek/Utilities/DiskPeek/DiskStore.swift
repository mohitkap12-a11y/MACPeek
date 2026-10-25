#if os(macOS)
import Foundation
import MacPeekCore
import DiskPeekKit

/// Observable state for DiskPeek. It samples per-process disk counters on a timer, but only while its screen is
/// on screen. Leaving the screen stops the timer and discards the baseline, so returning never shows a huge
/// "rate" computed over the time it was closed. Drive capacity is read on its own task when the screen opens and every
/// 30 s after, so a slow drive never holds up I/O sampling.
@MainActor
final class DiskStore: ObservableObject {
    @Published private(set) var activity: [DiskActivity] = []
    @Published private(set) var unreadableProcesses = 0
    @Published private(set) var isWaitingForSecondSample = true
    @Published private(set) var error: String?
    @Published var sort: DiskSort = .rate
    @Published private(set) var interval: TimeInterval = 2
    @Published private(set) var volumes: [VolumeCapacity] = []
    @Published private(set) var volumesError: String?
    /// False until the first drive read finishes, so "no drives" is not confused with "still reading".
    @Published private(set) var hasReadVolumes = false

    private let reader: DiskIOReading
    private let volumeReader: VolumeCapacityReading
    private let settings: AppSettings
    private var sampler = DiskIOSampler()
    private var pollTask: Task<Void, Never>?
    private var volumeTask: Task<Void, Never>?
    private static let volumeRefresh: TimeInterval = 30

    init(reader: DiskIOReading, volumeReader: VolumeCapacityReading, settings: AppSettings) {
        self.reader = reader
        self.volumeReader = volumeReader
        self.settings = settings
    }

    /// The rows to show, in the chosen order.
    var rows: [DiskActivity] { Array(DiskIOSampler.sorted(activity, by: sort).prefix(30)) }

    func startSampling() {
        stopSampling()
        sampler = DiskIOSampler()
        activity = []
        isWaitingForSecondSample = true
        volumeTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.readVolumes()
                try? await Task.sleep(nanoseconds: UInt64(Self.volumeRefresh * 1_000_000_000))
            }
        }
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
        volumeTask?.cancel()
        volumeTask = nil
    }

    private func readVolumes() async {
        let volumeReader = self.volumeReader
        do {
            let read = try await Task.detached(priority: .utility) { try volumeReader.read() }.value
            guard !Task.isCancelled else { return }
            volumes = read
            volumesError = nil
            hasReadVolumes = true
        } catch {
            if Task.isCancelled { return }
            volumes = []
            volumesError = error.localizedDescription
            hasReadVolumes = true
            Log.diskPeek.error("reading drive capacity failed: \(error.localizedDescription, privacy: .public)")
        }
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
