#if os(macOS)
import AppKit
import SwiftUI
import Combine
import MacPeekCore
import PortPeekKit
import VitalsKit

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate, NSWindowDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let router: UtilityRouter
    private let registry: UtilityRegistry
    private let settings: AppSettings
    private let monitor: VitalsMonitor
    private var observers: Set<AnyCancellable> = []
    private let remote: RemoteManagementController
    /// The launcher in a window: used when macOS hides the menu-bar icon (a full menu bar, or the notch), so MacPeek
    /// can still be opened by launching it again.
    private var window: NSWindow?
    private let makeContent: () -> AnyView

    init(router: UtilityRouter, registry: UtilityRegistry, settings: AppSettings, updater: UpdaterService,
         remote: RemoteManagementController, remoteIntro: RemoteIntroController, monitor: VitalsMonitor) {
        self.router = router
        self.registry = registry
        self.settings = settings
        self.remote = remote
        self.monitor = monitor
        makeContent = {
            AnyView(MainPopoverView()
                .environmentObject(router)
                .environmentObject(registry)
                .environmentObject(settings)
                .environmentObject(updater)
                .environmentObject(remote)
                .environmentObject(remoteIntro)
                .environmentObject(monitor))
        }
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 380, height: 640)
        popover.contentViewController = NSHostingController(rootView: makeContent())

        // The popover window does not reliably follow NSApp.appearance, so apply the chosen theme to it directly.
        popover.appearance = settings.appearance.nsAppearance
        settings.$appearance.sink { [weak self] mode in
            self?.popover.appearance = mode.nsAppearance
            self?.window?.appearance = mode.nsAppearance
        }
        .store(in: &observers)

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // While Remote management is on, the icon carries a dot and the tooltip says so: it is never on unseen. Open
        // tunnels are said too, and listed in the right-click menu with Close. The readout follows the monitor.
        remote.$isEnabled.sink { [weak self] _ in Task { @MainActor in self?.updateButton() } }.store(in: &observers)
        remote.$snapshot.sink { [weak self] _ in Task { @MainActor in self?.updateButton() } }.store(in: &observers)
        monitor.$latest.sink { [weak self] _ in Task { @MainActor in self?.updateButton() } }.store(in: &observers)
        settings.objectWillChange.sink { [weak self] _ in Task { @MainActor in self?.updateButton() } }.store(in: &observers)
        updateButton()
    }

    // MARK: - The button

    private func updateButton() {
        guard let button = statusItem.button else { return }
        let enabled = remote.isEnabled
        let tunnels = enabled ? remote.snapshot?.tunnels.count ?? 0 : 0
        let icon = MenuBarController.makeIcon(remote: enabled)
        let metrics = settings.menuBarMetrics
        let tunnelText = tunnels == 0 ? "" : tunnels == 1 ? ", 1 tunnel open" : ", \(tunnels) tunnels open"
        var description = enabled ? "MacPeek, Remote management on\(tunnelText)" : "MacPeek"
        if metrics.isEmpty {
            statusItem.length = NSStatusItem.squareLength
            button.attributedTitle = NSAttributedString(string: "")
            button.image = icon
            button.imagePosition = .imageOnly
        } else {
            let items = MenuBarReadout.items(for: metrics, sample: monitor.latest)
            statusItem.length = NSStatusItem.variableLength
            button.attributedTitle = Self.readoutTitle(items)
            if settings.menuBarShowsIcon || enabled {
                // The Remote dot must stay visible while Remote management is on, so the icon stays then too.
                button.image = icon
                button.imagePosition = .imageLeading
            } else {
                button.image = nil
                button.imagePosition = .noImage
            }
            description += ". " + MenuBarReadout.spokenText(items)
        }
        button.setAccessibilityLabel(description)
        button.toolTip = enabled ? "MacPeek — Remote management is on\(tunnelText)" : "MacPeek"
    }

    /// "CPU 42%  MEM 61%  ↓1.2M ↑30K  58°": labels small, values in a readable monospaced-digit font, warning and
    /// critical values in orange and red.
    static func readoutTitle(_ items: [ReadoutItem]) -> NSAttributedString {
        let title = NSMutableAttributedString()
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let labelFont = NSFont.systemFont(ofSize: 9, weight: .semibold)
        for (index, item) in items.enumerated() {
            if index > 0 { title.append(NSAttributedString(string: "  ", attributes: [.font: valueFont])) }
            if let label = item.label {
                title.append(NSAttributedString(string: label + " ", attributes: [.font: labelFont, .baselineOffset: 1]))
            }
            var attributes: [NSAttributedString.Key: Any] = [.font: valueFont]
            switch item.level {
            case .warning: attributes[.foregroundColor] = NSColor.systemOrange
            case .critical: attributes[.foregroundColor] = NSColor.systemRed
            case .normal: break
            }
            title.append(NSAttributedString(string: item.value, attributes: attributes))
        }
        return title
    }

    /// False when macOS hides the menu-bar item: the menu bar is full, or the item would sit under the notch.
    var isIconVisible: Bool {
        guard statusItem.isVisible, let window = statusItem.button?.window else { return false }
        guard window.occlusionState.contains(.visible) else { return false }
        return NSScreen.screens.contains { $0.frame.intersects(window.frame) }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        window?.close()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    /// Opens MacPeek on a screen: under the menu-bar icon when it can be seen, otherwise in a window.
    func show(_ route: Route = .launcher) {
        if isIconVisible {
            if !popover.isShown { showPopover() }
        } else {
            showWindow()
        }
        router.go(route)
    }

    /// MacPeek was launched again while running (from Finder, Spotlight or the Dock).
    func reopen() { show(.launcher) }

    private func showWindow() {
        if popover.isShown { popover.performClose(nil) }
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 640), styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "MacPeek"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: makeContent())
        window.appearance = settings.appearance.nsAppearance
        window.delegate = self
        window.center()
        self.window = window
        router.popoverWillShow()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        router.popoverDidClose()
        window = nil
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let tunnels = remote.isEnabled ? remote.snapshot?.tunnels ?? [] : []
        if !tunnels.isEmpty {
            menu.addItem(withTitle: tunnels.count == 1 ? "1 tunnel open" : "\(tunnels.count) tunnels open", action: nil, keyEquivalent: "")
            for tunnel in tunnels {
                let item = menu.addItem(withTitle: "Close port \(tunnel.port) (\(tunnel.consoleName))", action: #selector(closeTunnel(_:)),
                                        keyEquivalent: "")
                item.target = self
                item.representedObject = tunnel.id
            }
            menu.addItem(.separator())
        }
        if !monitor.recentAlerts.isEmpty {
            menu.addItem(withTitle: "Recent Alerts…", action: #selector(openAlerts), keyEquivalent: "").target = self
        }
        if settings.historyEnabled {
            menu.addItem(withTitle: "History…", action: #selector(openHistory), keyEquivalent: "").target = self
        }
        menu.addItem(withTitle: "Refresh", action: #selector(refreshNow), keyEquivalent: "r").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit MacPeek", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openAlerts() { show(.alerts) }
    @objc private func openHistory() { show(.history) }
    @objc private func refreshNow() { registry.refreshSummaries() }
    @objc private func closeTunnel(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        remote.closeTunnel(id)
    }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: NSPopoverDelegate — utilities refresh only while their screen is visible.

    func popoverWillShow(_ notification: Notification) { router.popoverWillShow() }
    func popoverDidClose(_ notification: Notification) { router.popoverDidClose() }

    /// Monochrome template icon: a magnifier ("peek") whose lens holds a dot.
    /// Template images adapt automatically to light/dark menu bars and Retina. With `remote`, a dot at the top right
    /// shows that Remote management is on.
    static func makeIcon(remote: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let lens = NSBezierPath(ovalIn: NSRect(x: 2.5, y: 6.5, width: 9, height: 9))
            lens.lineWidth = 1.6
            lens.stroke()
            let handle = NSBezierPath()
            handle.move(to: NSPoint(x: 10.2, y: 7.8))
            handle.line(to: NSPoint(x: 15, y: 3))
            handle.lineWidth = 2
            handle.lineCapStyle = .round
            handle.stroke()
            NSBezierPath(ovalIn: NSRect(x: 5.4, y: 9.4, width: 3.2, height: 3.2)).fill()
            if remote { NSBezierPath(ovalIn: NSRect(x: 13, y: 12.5, width: 4.5, height: 4.5)).fill() }
            return true
        }
        image.isTemplate = true
        return image
    }
}
#endif
