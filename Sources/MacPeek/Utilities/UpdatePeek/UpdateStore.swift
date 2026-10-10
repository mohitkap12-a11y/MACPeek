#if os(macOS)
import Foundation
import UpdatePeekKit

/// Observable state for UpdatePeek. The macOS version and "are Homebrew and npm installed?" are cheap local reads. Each
/// package manager runs only when the user presses its Check button (npm asks its registry, so that is a network request),
/// and an in-flight check is cancelled when the screen is left.
@MainActor
final class UpdateStore: ObservableObject {
    @Published private(set) var operatingSystem: OperatingSystemInfo
    @Published private(set) var homebrew: PackageCheckState
    @Published private(set) var npm: PackageCheckState

    private let service: UpdateStatusService
    private var homebrewTask: Task<Void, Never>?
    private var npmTask: Task<Void, Never>?

    init(service: UpdateStatusService) {
        self.service = service
        self.operatingSystem = service.operatingSystem()
        self.homebrew = service.initialHomebrewState()
        self.npm = service.initialNpmState()
    }

    /// Re-reads the local facts when the screen opens, keeping a finished or running result.
    func reload() {
        operatingSystem = service.operatingSystem()
        if !Self.keepsResult(homebrew) { homebrew = service.initialHomebrewState() }
        if !Self.keepsResult(npm) { npm = service.initialNpmState() }
    }

    private static func keepsResult(_ state: PackageCheckState) -> Bool {
        switch state {
        case .checked, .checking: return true
        default: return false
        }
    }

    func checkHomebrew() {
        if case .checking = homebrew { return }
        homebrewTask?.cancel()
        homebrew = .checking
        homebrewTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.service.checkHomebrew()
            guard !Task.isCancelled else { return }
            self.homebrew = result
            if case .failed = result { Log.updatePeek.error("homebrew check failed") }
        }
    }

    func checkNpm() {
        if case .checking = npm { return }
        npmTask?.cancel()
        npm = .checking
        npmTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.service.checkNpm()
            guard !Task.isCancelled else { return }
            self.npm = result
            if case .failed = result { Log.updatePeek.error("npm check failed") }
        }
    }

    func cancel() {
        homebrewTask?.cancel(); homebrewTask = nil
        npmTask?.cancel(); npmTask = nil
        if case .checking = homebrew { homebrew = service.initialHomebrewState() }
        if case .checking = npm { npm = service.initialNpmState() }
    }
}
#endif
