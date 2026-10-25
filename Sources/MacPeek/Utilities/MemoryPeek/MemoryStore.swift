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
    @Published private(set) var unreadableProcesses = 0
    @Published private(set) var error: String?
    @Published private(set) var processError: String?
    @Published private(set) var interval: TimeInterval = 2

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

    /// One read for the launcher line. Cheap: a few sysctl and Mach calls, no process scan.
    func launcherSummary() async -> String? {
        let reader = self.reader
        guard let stats = try? await Task.detached(priority: .utility, operation: { try reader.read() }).value else { return nil }
        return MemoryAssessment.launcherSummary(stats)
    }

    func startPolling() {
        stopPolling()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                let seconds = max(self.settings.refreshInterval, 2)
                self.interval = seconds
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
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
        } catch {
            if Task.isCancelled { return }
            stats = nil
            self.error = error.localizedDescription
            Log.memoryPeek.error("reading memory failed: \(error.localizedDescription, privacy: .public)")
        }

        let processReader = self.processReader
        do {
            let flag = ProcessScanCancellation()
            let snapshot = try await withTaskCancellationHandler {
                try await Task.detached(priority: .utility) { try processReader.read(isCancelled: { flag.isCancelled }) }.value
            } onCancel: {
                flag.cancel()
            }
            guard !Task.isCancelled else { return }
            topProcesses = MemoryAssessment.topProcesses(snapshot.usages)
            unreadableProcesses = snapshot.unreadable
            processError = nil
        } catch {
            if Task.isCancelled { return }
            topProcesses = []
            unreadableProcesses = 0
            processError = error.localizedDescription
            Log.memoryPeek.error("reading processes failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
#endif
