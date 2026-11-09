#if os(macOS)
import Foundation
import MacPeekCore
import GPUPeekKit

/// Observable state for GPUPeek. Reads the GPU statistics, its clients, Metal's facts and (on Apple silicon) the power
/// counters every `refreshInterval` seconds while the screen is open; per-process GPU time and power need two readings, so
/// they appear from the second sample. History is "since opened" and is dropped when the screen is left.
@MainActor
final class GPUStore: ObservableObject {
    @Published private(set) var snapshot: GPUSnapshot?
    @Published private(set) var error: String?
    @Published private(set) var utilizationHistory = RecentValues()
    @Published private(set) var neuralEngineHistory = RecentValues()
    /// The highest Neural Engine power seen since the screen opened: the scale for its ring and chart line, since macOS
    /// publishes no maximum.
    @Published private(set) var neuralEnginePeakWatts = 0.0

    private let reader: GPUReading
    private let settings: AppSettings
    private var task: Task<Void, Never>?
    private var previousClients: [GPUClient]?
    private var previousDate: Date?

    init(reader: GPUReading, settings: AppSettings) {
        self.reader = reader
        self.settings = settings
    }

    /// The launcher ring: one `ioreg` read of the primary GPU. Never samples power, so the screen's power interval is not
    /// disturbed. A driver that reports no utilization shows "–", never a made-up 0 %.
    func launcherGauge() async -> LauncherGauge? {
        guard let gpu = try? await reader.gpus().first else { return nil }
        if let reading = GPUAssessment.gaugeReading(gpu) { return LauncherGauge(reading, tint: .accent) }
        return LauncherGauge(fraction: 0, value: "–", caption: GPUAssessment.caption(gpu))
    }

    func sample() async {
        let now = Date()
        let interval = previousDate.map { now.timeIntervalSince($0) } ?? 0
        do {
            let (result, clients) = try await reader.snapshot(previousClients: previousClients, interval: interval)
            guard !Task.isCancelled else { return }
            snapshot = result
            previousClients = clients
            previousDate = now
            error = nil
            if let utilization = result.primary?.deviceUtilization { utilizationHistory.append(utilization) }
            if let watts = result.power?.neuralEngineWatts {
                neuralEngineHistory.append(watts)
                neuralEnginePeakWatts = max(neuralEnginePeakWatts, watts)
            }
        } catch {
            if Task.isCancelled { return }
            self.error = error.localizedDescription
            Log.gpuPeek.error("read failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func startSampling() {
        stopSampling()
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.sample()
                let seconds = min(max(self.settings.refreshInterval, 1), 3600)
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
        }
    }

    func stopSampling() {
        task?.cancel()
        task = nil
        previousClients = nil
        previousDate = nil
        utilizationHistory.removeAll()
        neuralEngineHistory.removeAll()
        neuralEnginePeakWatts = 0
    }
}
#endif
