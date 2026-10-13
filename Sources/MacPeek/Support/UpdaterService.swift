#if os(macOS)
import AppKit
import Combine
import Sparkle

/// In-app updates through Sparkle. The update feed is a GitHub release asset (`SUFeedURL` in Info.plist) and every
/// update archive is verified against the EdDSA public key in `SUPublicEDKey`, so a tampered download is rejected.
///
/// Sparkle only runs from a packaged release build that carries a real public key. `swift run` builds and local
/// ad-hoc builds have none, so the updater stays off there and the UI says so instead of failing.
@MainActor
final class UpdaterService: NSObject, ObservableObject, SPUStandardUserDriverDelegate {
    /// True when this build can check for updates (packaged app with a real `SUPublicEDKey`).
    let isAvailable: Bool
    @Published private(set) var canCheckForUpdates = false
    /// Mirrors Sparkle's "check automatically" setting (about once a day). Sparkle persists it in UserDefaults.
    @Published var automaticallyChecks: Bool {
        didSet { controller?.updater.automaticallyChecksForUpdates = automaticallyChecks }
    }

    private var controller: SPUStandardUpdaterController?
    private var cancellable: AnyCancellable?

    override init() {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        isAvailable = Bundle.main.bundleURL.pathExtension == "app" && !key.isEmpty && !key.hasPrefix("__")
        automaticallyChecks = false
        super.init()
        guard isAvailable else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
        cancellable = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.canCheckForUpdates = value }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    // MARK: SPUStandardUserDriverDelegate
    // MacPeek has no Dock icon or main window, so bring Sparkle's alert to the front when it shows an update.

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard handleShowingUpdate else { return }
        Task { @MainActor in NSApp.activate(ignoringOtherApps: true) }
    }
}
#endif
