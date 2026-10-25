#if os(macOS)
import Foundation
import MacPeekCore
import CPUPeekKit

/// Observable state for CPUPeek. It samples CPU ticks and per-process CPU time on a timer, only while its screen is
/// open. Leaving the screen stops the timer and discards the baseline, so returning never shows usage computed over
/// the time it was closed.
@MainActor
final class CPUStore: ObservableObject {
    @Published private(set) var usage: CPUUsage?
    @Published private(set) var snapshot: CPUSnapshot?
    @Published private(set) var processes: [ProcessCPURow] = []
    @Published private(set) var unreadableProcesses = 0
    @Published private(set) var topology: CPUTopology?
    @Published private(set) var isWaitingForSecondSample = true
    @Published private(set) var error: String?
    @Published private(set) var processError: String?
    @Published private(set) var interval: TimeInterval = 2

    private let reader: CPUReading
    private let processReader: ProcessUsageReading
    private let settings: AppSettings
    private var previousCores: [CoreTicks]?
    private var sampler = ProcessCPUSampler()
    private var pollTask: Task<Void, Never>?

    init(reader: CPUReading, processReader: ProcessUsageReading, settings: AppSettings) {
        self.reader = reader
        self.processReader = processReader
        self.settings = settings
    }

    var headline: String? {
        guard let usage else { return nil }
        return CPUAssessment.headline(usage: usage, top: processes.first, thermal: snapshot?.thermal)
    }

    /// One read for the launcher line: load average and thermal state, no sampling.
    func launcherSummary() async -> String? {
        let reader = self.reader
        guard let snapshot = try? await Task.detached(priority: .utility, operation: { try reader.snapshot() }).value else { return nil }
        return CPUAssessment.launcherSummary(snapshot)
    }

    func startSampling() {
        stopSampling()
        previousCores = nil
        sampler = ProcessCPUSampler()
        usage = nil
        processes = []
        isWaitingForSecondSample = true
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.readTopologyIfNeeded()
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

    private func readTopologyIfNeeded() async {
        guard topology == nil else { return }
        let reader = self.reader
        topology = await Task.detached(priority: .utility) { reader.topology() }.value
    }

    private func tick() async {
        let reader = self.reader
        do {
            let read = try await Task.detached(priority: .utility) { try reader.snapshot() }.value
            guard !Task.isCancelled else { return }
            if let previousCores { usage = CoreUsage.between(previousCores, read.cores) ?? usage }
            previousCores = read.cores
            snapshot = read
            error = nil
        } catch {
            if Task.isCancelled { return }
            // A gap invalidates the baseline, and stale usage must not look current.
            previousCores = nil
            usage = nil
            snapshot = nil
            self.error = error.localizedDescription
            Log.cpuPeek.error("reading CPU load failed: \(error.localizedDescription, privacy: .public)")
        }

        let processReader = self.processReader
        do {
            let flag = ProcessScanCancellation()
            let result = try await withTaskCancellationHandler {
                try await Task.detached(priority: .utility) { try processReader.read(isCancelled: { flag.isCancelled }) }.value
            } onCancel: {
                flag.cancel()
            }
            guard !Task.isCancelled else { return }
            processes = Array(sampler.ingest(result.usages, at: Date()).prefix(20))
            unreadableProcesses = result.unreadable
            processError = nil
        } catch {
            if Task.isCancelled { return }
            sampler = ProcessCPUSampler()
            processes = []
            unreadableProcesses = 0
            processError = error.localizedDescription
            Log.cpuPeek.error("reading processes failed: \(error.localizedDescription, privacy: .public)")
        }
        // A failing process scan is shown on its card; it must not hold the whole screen on "first sample".
        isWaitingForSecondSample = usage == nil || (processError == nil && sampler.isBaselineOnly)
    }
}
#endif
