#if os(macOS)
import Foundation
import UpdatePeekKit

/// Observable state for UpdatePeek. The macOS version, what macOS's own record says about updates, and "are Homebrew and
/// npm installed?" are cheap local reads. Everything else runs only when the user presses a button: Check now (asks Apple's
/// update servers), Homebrew's Check, npm's Check (asks the npm registry) and an npm package's Update (after a
/// confirmation). Checks are cancelled when the screen is left; an update that has started is not, so it is never
/// interrupted halfway.
@MainActor
final class UpdateStore: ObservableObject {
    @Published private(set) var operatingSystem: OperatingSystemInfo
    @Published private(set) var macOS: MacOSUpdateState
    @Published private(set) var homebrew: PackageCheckState
    @Published private(set) var npm: PackageCheckState
    /// The npm package being updated right now (`OutdatedPackage.id`), if any.
    @Published private(set) var updatingNpm: String?
    @Published private(set) var npmNotice: Banner?

    private let service: UpdateStatusService
    private var macOSTask: Task<Void, Never>?
    private var homebrewTask: Task<Void, Never>?
    private var npmTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?
    private var isVisible = false

    init(service: UpdateStatusService) {
        self.service = service
        self.operatingSystem = service.operatingSystem()
        self.macOS = service.initialMacOSState()
        self.homebrew = service.initialHomebrewState()
        self.npm = service.initialNpmState()
    }

    /// Re-reads the local facts when the screen opens, keeping a finished or running result.
    func reload() {
        isVisible = true
        operatingSystem = service.operatingSystem()
        if !Self.keepsResult(macOS) { macOS = service.initialMacOSState() }
        if !Self.keepsResult(homebrew) { homebrew = service.initialHomebrewState() }
        if !Self.keepsResult(npm) { npm = service.initialNpmState() }
    }

    /// Everything shown on the launcher: the version, plus how many updates macOS has reported.
    var launcherSummary: String {
        if case .known(let report) = macOS, !report.updates.isEmpty {
            return "\(operatingSystem.displayString) · \(report.updates.count) update\(report.updates.count == 1 ? "" : "s") found"
        }
        return operatingSystem.displayString
    }

    private static func keepsResult(_ state: PackageCheckState) -> Bool {
        switch state {
        case .checked, .checking: return true
        default: return false
        }
    }

    private static func keepsResult(_ state: MacOSUpdateState) -> Bool {
        switch state {
        case .known, .checking: return true
        default: return false
        }
    }

    func checkMacOS() {
        if case .checking = macOS { return }
        macOSTask?.cancel()
        macOS = .checking
        macOSTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.service.checkMacOS()
            guard !Task.isCancelled else { return }
            self.macOS = result
            if case .failed = result { Log.updatePeek.error("macOS update check failed") }
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

    func checkNpm(keepingNotice: Bool = false) {
        if case .checking = npm { return }
        npmTask?.cancel()
        if !keepingNotice { npmNotice = nil }
        npm = .checking
        npmTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.service.checkNpm()
            guard !Task.isCancelled else { return }
            self.npm = result
            if case .failed = result { Log.updatePeek.error("npm check failed") }
        }
    }

    /// Updates one npm package to the latest version npm reported. The view asks the user to confirm first. One update at a
    /// time; afterwards npm is asked again (if the screen is still open) so the list shows what is really left.
    func updateNpm(_ package: OutdatedPackage) {
        guard updatingNpm == nil, case .checked(let report) = npm, report.packages.contains(package) else { return }
        updatingNpm = package.id
        npmNotice = nil
        let known = report.packages
        let service = self.service
        updateTask = Task { [weak self] in
            let outcome = await service.updateNpmPackage(package, among: known)
            guard let self else { return }
            self.updatingNpm = nil
            switch outcome {
            case .installed:
                self.npmNotice = Banner(kind: .success, text: "Updated \(package.name). Checking npm again…")
                if self.isVisible {
                    self.checkNpm(keepingNotice: true)
                } else {
                    self.npm = self.service.initialNpmState()
                }
            case .failed(let message):
                Log.updatePeek.error("npm update failed")
                self.npmNotice = Banner(kind: .error, text: message)
            }
        }
    }

    func cancel() {
        isVisible = false
        macOSTask?.cancel(); macOSTask = nil
        homebrewTask?.cancel(); homebrewTask = nil
        npmTask?.cancel(); npmTask = nil
        if case .checking = macOS { macOS = service.initialMacOSState() }
        if case .checking = homebrew { homebrew = service.initialHomebrewState() }
        if case .checking = npm { npm = service.initialNpmState() }
    }
}
#endif
