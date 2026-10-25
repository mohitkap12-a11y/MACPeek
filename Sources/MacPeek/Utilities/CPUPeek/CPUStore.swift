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
    /// The process list needs its own second sample (after opening, or after a failed scan) and says so on its card.
    @Published private(set) var isMeasuringProcesses = true
    @Published private(set) var error: String?
    @Published private(set) var processError: String?
    @Published private(set) var interval: TimeInterval = 2
    /// Overall CPU use for each interval since the screen opened.
    @Published private(set) var history = RecentValues()

    private let reader: CPUReading
    private let processReader: ProcessUsageReading
    private let settings: AppSettings
    private var previousCores: [CoreTicks]?
    /// The launcher's latest CPU reading. When the screen opens soon after, it is the baseline, so CPU use shows at once.
    private var launcherCores: (date: Date, cores: [CoreTicks])?
    private static let launcherBaselineAge: TimeInterval = 15
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

    /// The launcher ring: overall use since the previous launcher reading when that is recent (so live updates cost
    /// one read each), otherwise two readings a third of a second apart; plus the load average, or "running hot" when
    /// macOS reports a high thermal state. A one-shot read, never polling.
    func launcherGauge() async -> LauncherGauge? {
        let reader = self.reader
        let previous = launcherCores.flatMap { Date().timeIntervalSince($0.date) < Self.launcherBaselineAge ? $0.cores : nil }
        let reading = await Task.detached(priority: .utility) { () async -> (usage: CPUUsage, snapshot: CPUSnapshot)? in
            if let previous, let now = try? reader.snapshot(), let usage = CoreUsage.between(previous, now.cores) {
                return (usage, now)
            }
            guard let first = try? reader.snapshot() else { return nil }
            try? await Task.sleep(nanoseconds: 330_000_000)
            guard let second = try? reader.snapshot(), let usage = CoreUsage.between(first.cores, second.cores) else { return nil }
            return (usage, second)
        }.value
        guard let reading else { return nil }
        launcherCores = (Date(), reading.snapshot.cores)
        return LauncherGauge(CPUAssessment.gaugeReading(usage: reading.usage, snapshot: reading.snapshot), tint: .accent)
    }

    func startSampling() {
        stopSampling()
        // A launcher reading from a moment ago is a fine baseline: overall use appears with the first sample.
        if let recent = launcherCores, Date().timeIntervalSince(recent.date) < Self.launcherBaselineAge {
            previousCores = recent.cores
        } else {
            previousCores = nil
        }
        sampler = ProcessCPUSampler()
        usage = nil
        processes = []
        snapshot = nil
        error = nil
        processError = nil
        isWaitingForSecondSample = true
        isMeasuringProcesses = true
        history.removeAll()
        pollTask = Task { [weak self] in
            var samples = 0
            while !Task.isCancelled {
                guard let self else { return }
                await self.readTopologyIfNeeded()
                await self.tick()
                samples += 1
                let seconds = self.settings.refreshInterval
                self.interval = seconds
                try? await Task.sleep(nanoseconds: SamplingSchedule.nanoseconds(SamplingSchedule.delay(afterSample: samples, interval: seconds)))
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
            // No comparable previous reading (first sample, or the core count changed): show nothing rather than old usage.
            usage = previousCores.flatMap { CoreUsage.between($0, read.cores) }
            if let usage { history.append(usage.total) }
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
            let flag = CancellationFlag()
            let result = try await withTaskCancellationHandler {
                try await Task.detached(priority: .utility) { try processReader.read(isCancelled: { flag.isCancelled }) }.value
            } onCancel: {
                flag.cancel()
            }
            guard !Task.isCancelled else { return }
            processes = Array(sampler.ingest(result.usages, at: Date()).prefix(20))
            unreadableProcesses = result.unreadable
            processError = nil
            isMeasuringProcesses = sampler.isBaselineOnly
        } catch {
            if Task.isCancelled { return }
            sampler = ProcessCPUSampler()
            processes = []
            unreadableProcesses = 0
            processError = error.localizedDescription
            isMeasuringProcesses = true
            Log.cpuPeek.error("reading processes failed: \(error.localizedDescription, privacy: .public)")
        }
        // Only overall CPU use gates the screen; the process card shows its own measuring and error states.
        isWaitingForSecondSample = usage == nil
    }
}
#endif
