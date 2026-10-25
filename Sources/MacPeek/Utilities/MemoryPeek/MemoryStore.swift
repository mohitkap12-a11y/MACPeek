#if os(macOS)
import Foundation
import MacPeekCore
import MemoryPeekKit

/// Observable state for MemoryPeek. It reads system memory and per-process footprints on a timer, only while its
/// screen is open.
@MainActor
final class MemoryStore: ObservableObject {
    @Published private(set) var stats: MemoryStats?
    @Published private(set) var topProcesses: [ProcessMemoryRow] = []
    @Published private(set) var error: String?
    @Published private(set) var processError: String?
    /// False until the first process scan of this visit finishes.
    @Published private(set) var hasReadProcesses = false
    @Published private(set) var interval: TimeInterval = 2
    /// Memory in use (fraction of installed) for each read since the screen opened.
    @Published private(set) var history = RecentValues()

    private let reader: MemoryReading
    private let processReader: ProcessUsageReading
    private let settings: AppSettings
    private var pollTask: Task<Void, Never>?

    init(reader: MemoryReading, processReader: ProcessUsageReading, settings: AppSettings) {
        self.reader = reader
        self.processReader = processReader
        self.settings = settings
    }

    var breakdown: MemoryBreakdown? { stats.map(MemoryBreakdown.init) }
    var assessment: MemoryAssessment? { stats.map(MemoryAssessment.init(stats:)) }

    /// One read for the launcher ring: memory in use, tinted red when pressure is critical. A few sysctl and Mach
    /// calls, no process scan.
    func launcherGauge() async -> LauncherGauge? {
        let reader = self.reader
        guard let stats = try? await Task.detached(priority: .utility, operation: { try reader.read() }).value,
              let reading = MemoryAssessment.gaugeReading(stats) else { return nil }
        return LauncherGauge(reading, tint: .amber)
    }

    func startPolling() {
        stopPolling()
        // Never show the last visit's figures (or error) as current while the first read runs.
        stats = nil
        topProcesses = []
        error = nil
        processError = nil
        hasReadProcesses = false
        history.removeAll()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                let seconds = self.settings.refreshInterval
                self.interval = seconds
                try? await Task.sleep(nanoseconds: SamplingSchedule.nanoseconds(seconds))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func tick() async {
        let reader = self.reader
        do {
            let read = try await Task.detached(priority: .utility) { try reader.read() }.value
            guard !Task.isCancelled else { return }
            stats = read
            error = nil
            if read.physicalBytes > 0 { history.append(Double(MemoryBreakdown(read).used) / Double(read.physicalBytes)) }
        } catch {
            if Task.isCancelled { return }
            stats = nil
            self.error = error.localizedDescription
            Log.memoryPeek.error("reading memory failed: \(error.localizedDescription, privacy: .public)")
        }

        let processReader = self.processReader
        do {
            let flag = CancellationFlag()
            let snapshot = try await withTaskCancellationHandler {
                try await Task.detached(priority: .utility) { try processReader.read(isCancelled: { flag.isCancelled }) }.value
            } onCancel: {
                flag.cancel()
            }
            guard !Task.isCancelled else { return }
            topProcesses = MemoryAssessment.topProcesses(snapshot.usages)
            processError = nil
            hasReadProcesses = true
        } catch {
            if Task.isCancelled { return }
            topProcesses = []
            processError = error.localizedDescription
            hasReadProcesses = true
            Log.memoryPeek.error("reading processes failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
#endif
