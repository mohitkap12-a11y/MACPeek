#if os(macOS)
import Foundation
import ModelPeekKit

/// Observable state for ModelPeek. Reads runners every few seconds while the screen is open; CPU and GPU need two
/// readings, so they appear from the second one. Nothing runs in the background.
@MainActor
final class ModelStore: ObservableObject {
    @Published private(set) var snapshot: ModelSnapshot?
    @Published private(set) var error: String?

    private let reader: ModelReading
    private let settings: AppSettings
    private var task: Task<Void, Never>?
    private var previous: ModelSamplingState?

    init(reader: ModelReading, settings: AppSettings) {
        self.reader = reader
        self.settings = settings
    }

    func refreshOnce() async {
        do {
            let (result, state) = try await reader.snapshot(previous: previous)
            guard !Task.isCancelled else { return }
            snapshot = result
            previous = state
            error = nil
        } catch {
            if Task.isCancelled { return }
            self.error = error.localizedDescription
            Log.modelPeek.error("read failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func startPolling() {
        stopPolling()
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshOnce()
                let seconds = max(self.settings.refreshInterval, 3)
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
        }
    }

    func stopPolling() {
        task?.cancel()
        task = nil
        previous = nil
    }
}
#endif
