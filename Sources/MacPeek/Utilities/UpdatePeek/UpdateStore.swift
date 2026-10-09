#if os(macOS)
import Foundation
import UpdatePeekKit

/// Observable state for UpdatePeek. The macOS version and "is Homebrew installed?" are cheap local reads. Homebrew runs
/// only when the user presses Check, and an in-flight check is cancelled when the screen is left.
@MainActor
final class UpdateStore: ObservableObject {
    @Published private(set) var operatingSystem: OperatingSystemInfo
    @Published private(set) var homebrew: HomebrewState

    private let service: UpdateStatusService
    private var task: Task<Void, Never>?

    init(service: UpdateStatusService) {
        self.service = service
        self.operatingSystem = service.operatingSystem()
        self.homebrew = service.initialHomebrewState()
    }

    /// Re-reads the local facts when the screen opens, keeping a finished Homebrew result.
    func reload() {
        operatingSystem = service.operatingSystem()
        if case .checked = homebrew { return }
        if case .checking = homebrew { return }
        homebrew = service.initialHomebrewState()
    }

    func checkHomebrew() {
        if case .checking = homebrew { return }
        task?.cancel()
        homebrew = .checking
        task = Task { [weak self] in
            guard let self else { return }
            let result = await self.service.checkHomebrew()
            guard !Task.isCancelled else { return }
            self.homebrew = result
            if case .failed = result { Log.updatePeek.error("homebrew check failed") }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if case .checking = homebrew { homebrew = service.initialHomebrewState() }
    }
}
#endif
