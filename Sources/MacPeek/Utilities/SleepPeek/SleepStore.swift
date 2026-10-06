#if os(macOS)
import Foundation
import SleepPeekKit

/// Observable state for SleepPeek. The assertion snapshot is cheap and refreshes while the screen is visible.
/// The sleep/wake history comes from `pmset -g log`, which can take tens of seconds, so it only loads when asked.
@MainActor
final class SleepStore: ObservableObject {
    enum HistoryState: Equatable {
        case idle
        case loading
        case loaded(SleepHistory)
        case failed(String)
    }

    @Published private(set) var snapshot: SleepSnapshot?
    @Published private(set) var error: String?
    @Published private(set) var history: HistoryState = .idle

    private let reader: SleepReading
    private let settings: AppSettings
    private var pollTask: Task<Void, Never>?
    private var historyTask: Task<Void, Never>?

    init(reader: SleepReading, settings: AppSettings) {
        self.reader = reader
        self.settings = settings
    }

    /// One-off refresh (launcher summary, manual refresh).
    func refresh() async {
        do {
            let result = try await reader.snapshot()
            guard !Task.isCancelled else { return }
            snapshot = result
            error = nil
        } catch {
            if Task.isCancelled { return }
            self.error = error.localizedDescription
            Log.sleepPeek.error("read failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func startPolling() {
        stopPolling()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                // `pmset` is cheap, but there is no reason to run it more than every few seconds.
                let seconds = max(self.settings.refreshInterval, 5)
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
        }
    }

    /// Stops polling and any history read. A finished history stays on screen for the next visit.
    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        if history == .loading {
            historyTask?.cancel()
            historyTask = nil
            history = .idle
        }
    }

    func loadHistory() {
        historyTask?.cancel()
        history = .loading
        historyTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.reader.history(limit: 60)
                guard !Task.isCancelled else { return }
                self.history = .loaded(result)
            } catch {
                if Task.isCancelled { return }
                self.history = .failed(error.localizedDescription)
                Log.sleepPeek.error("history failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
#endif
