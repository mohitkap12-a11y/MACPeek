#if os(macOS)
import AppKit
import SwiftUI

/// The first launch, and a hidden icon. On the very first launch MacPeek opens itself so people see where it lives. When
/// macOS hides its icon (the menu bar is full, or the icon would sit under the notch) a small window says so and how to
/// make room, at most once a week: menu-bar apps otherwise look as if they never started.
@MainActor
final class WelcomeController {
    static let firstLaunchKey = "welcome.shown"
    static let hiddenHintKey = "welcome.hiddenHintShownAt"
    static let hiddenHintInterval: TimeInterval = 7 * 24 * 60 * 60
    static let iceURL = URL(string: "https://github.com/jordanbaird/Ice")!

    private let menuBar: MenuBarController
    private let defaults: UserDefaults
    private var window: NSWindow?

    init(menuBar: MenuBarController, defaults: UserDefaults = .standard) {
        self.menuBar = menuBar
        self.defaults = defaults
    }

    func start() {
        // The status item needs a moment to be placed before its visibility means anything.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self?.check()
        }
    }

    private func check() {
        let firstLaunch = !defaults.bool(forKey: Self.firstLaunchKey)
        defaults.set(true, forKey: Self.firstLaunchKey)
        if menuBar.isIconVisible {
            if firstLaunch { menuBar.show(.launcher) }
            return
        }
        let last = defaults.object(forKey: Self.hiddenHintKey) as? Date
        guard firstLaunch || last.map({ Date().timeIntervalSince($0) >= Self.hiddenHintInterval }) ?? true else { return }
        defaults.set(Date(), forKey: Self.hiddenHintKey)
        showHiddenIconWindow()
    }

    private func showHiddenIconWindow() {
        let view = HiddenIconView(
            open: { [weak self] in
                self?.window?.close()
                self?.menuBar.show(.launcher)
            },
            getIce: { NSWorkspace.shared.open(Self.iceURL) },
            close: { [weak self] in self?.window?.close() })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 300), styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "MacPeek is running"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: view)
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private struct HiddenIconView: View {
    let open: () -> Void
    let getIce: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "menubar.rectangle").font(.system(size: 26)).foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                Text("MacPeek is running, but macOS is hiding its icon").font(.headline)
            }
            Text("Your menu bar is full, so macOS left MacPeek's icon out. On a Mac with a notch, icons that would sit under it are hidden too.")
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 4) {
                Text("To make room:").font(.subheadline.weight(.semibold))
                Text("• Quit or turn off menu-bar items you do not use (hold ⌘ and drag one out to remove it).")
                Text("• Or use a menu-bar manager such as Ice, which is free and open source.")
                Text("• Until then, open MacPeek again from Applications or Spotlight to see it in a window.")
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack {
                Button("Get Ice…", action: getIce)
                Spacer()
                Button("Close", action: close).keyboardShortcut(.cancelAction)
                Button("Open MacPeek", action: open).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420, height: 300)
    }
}
#endif
