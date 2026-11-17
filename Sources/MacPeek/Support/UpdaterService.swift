#if os(macOS)
import AppKit
import Combine
import Sparkle

/// In-app updates through Sparkle. The update feed is a GitHub release asset (`SUFeedURL` in Info.plist) and every
/// update archive is verified against the EdDSA public key in `SUPublicEDKey`, so a tampered download is rejected.
///
/// Sparkle only runs from a packaged release build that carries a real public key. `swift run` builds and local
/// ad-hoc builds have none, so the updater stays off there and the UI says so instead of failing.
///
/// Preview builds: a Mac with the hidden `receivePreviewBuilds` default reads the preview feed (`MacPeekPreviewFeedURL`
/// in Info.plist, `appcast-beta.xml`) instead of `SUFeedURL`, so `v*-beta.N` tags reach only opted-in Macs
/// (docs/release.md, "Preview builds").
///
///     defaults write app.macpeek.MacPeek receivePreviewBuilds -bool YES     # opt in
///     defaults delete app.macpeek.MacPeek receivePreviewBuilds              # back to stable
@MainActor
final class UpdaterService: NSObject, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    /// The hidden opt-in for preview (beta) builds. Not shown in the UI until it is set.
    nonisolated static let previewBuildsKey = "receivePreviewBuilds"

    /// True when this Mac reads the preview feed. Settings shows it only while true, with a way back to stable.
    @Published private(set) var receivesPreviewBuilds = UserDefaults.standard.bool(forKey: UpdaterService.previewBuildsKey)

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
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        self.controller = controller
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
        cancellable = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.canCheckForUpdates = value }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    /// Leave the preview feed. Sparkle never downgrades, so the preview stays installed until a newer stable release.
    func stopPreviewBuilds() {
        UserDefaults.standard.removeObject(forKey: Self.previewBuildsKey)
        receivesPreviewBuilds = false
    }

    // MARK: SPUUpdaterDelegate

    /// nil keeps `SUFeedURL` (stable). With the opt-in set, the preview feed from `MacPeekPreviewFeedURL`.
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        guard UserDefaults.standard.bool(forKey: Self.previewBuildsKey),
              let preview = Bundle.main.object(forInfoDictionaryKey: "MacPeekPreviewFeedURL") as? String,
              preview.hasPrefix("https://") else { return nil }
        return preview
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
