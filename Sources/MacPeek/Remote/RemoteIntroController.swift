#if os(macOS)
import AppKit
import SwiftUI

/// The introduction to MacPeek Remote: a window of its own with a few pictures of the console and a link to its
/// website. It opens by itself once after the update that brought it, and again a week after "Remind Me Later",
/// until the person chooses "Never show this again" or follows the link. The launcher's MacPeek Remote row opens it
/// at any time, whatever was chosen.
///
/// Nothing is sent anywhere: the pictures are in the app, and the website opens only when the person asks.
@MainActor
final class RemoteIntroController: NSObject, ObservableObject, NSWindowDelegate {
    static let website = URL(string: "https://remote.macpeekapp.com/")!
    /// How long "Remind Me Later" waits.
    static let remindAfter: TimeInterval = 7 * 24 * 60 * 60

    private static let neverKey = "remoteIntroNeverShow"
    private static let remindAtKey = "remoteIntroRemindAt"

    private let settings: AppSettings
    private let defaults: UserDefaults
    private var window: NSWindow?
    private var timer: Timer?
    /// Set when a button answered the window, so closing it any other way counts as "Remind Me Later".
    private var answered = false

    init(settings: AppSettings, defaults: UserDefaults = .standard) {
        self.settings = settings
        self.defaults = defaults
        super.init()
    }

    /// Whether the window should open by itself now: not turned off, and no reminder still waiting.
    static func isDue(never: Bool, remindAt: TimeInterval, now: TimeInterval) -> Bool {
        !never && now >= remindAt
    }

    private var dueNow: Bool {
        Self.isDue(never: defaults.bool(forKey: Self.neverKey), remindAt: defaults.double(forKey: Self.remindAtKey),
                   now: Date().timeIntervalSince1970)
    }

    /// Called once at launch: shows the window a moment later if it is due, and checks again every few hours, since
    /// a menu-bar app can run for weeks without a restart.
    func start() {
        Task { @MainActor [weak self] in
            // A moment after launch, so it does not appear before the menu-bar icon does.
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            self?.showIfDue()
        }
        let timer = Timer(timeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.showIfDue() }
        }
        timer.tolerance = 10 * 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func showIfDue() {
        guard dueNow, window?.isVisible != true else { return }
        show()
    }

    /// Opens the window (from the launcher's row, or by itself).
    func show() {
        answered = false
        let window = self.window ?? makeWindow()
        self.window = window
        window.appearance = settings.appearance.nsAppearance
        if !window.isVisible { window.center() }
        // MacPeek has no Dock icon, so it must be brought forward for its window to be seen.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: RemoteIntroView.size.width, height: RemoteIntroView.size.height),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "MacPeek Remote"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.delegate = self
        window.contentView = NSHostingView(rootView: RemoteIntroView().environmentObject(self).environmentObject(settings))
        return window
    }

    // MARK: Answers

    /// "Get MacPeek Remote": opens the website. The person has seen the introduction, so it does not open by itself again.
    func getRemote() {
        defaults.set(true, forKey: Self.neverKey)
        NSWorkspace.shared.open(Self.website)
        close()
    }

    func remindLater() {
        defaults.set(Date().timeIntervalSince1970 + Self.remindAfter, forKey: Self.remindAtKey)
        close()
    }

    func neverShowAgain() {
        defaults.set(true, forKey: Self.neverKey)
        close()
    }

    private func close() {
        answered = true
        window?.close()
    }

    // Closed with the red button or ⌘W, without an answer: ask again in a week rather than at the next launch.
    func windowWillClose(_ notification: Notification) {
        guard !answered else { return }
        answered = true
        if !defaults.bool(forKey: Self.neverKey) {
            defaults.set(Date().timeIntervalSince1970 + Self.remindAfter, forKey: Self.remindAtKey)
        }
    }
}
#endif
