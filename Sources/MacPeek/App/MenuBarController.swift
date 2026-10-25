#if os(macOS)
import AppKit
import SwiftUI
import Combine
import MacPeekCore
import PortPeekKit

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let router: UtilityRouter
    private let registry: UtilityRegistry
    private var appearanceObserver: AnyCancellable?
    private var remoteObserver: AnyCancellable?

    init(router: UtilityRouter, registry: UtilityRegistry, settings: AppSettings, updater: UpdaterService,
         remote: RemoteManagementController) {
        self.router = router
        self.registry = registry
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 380, height: 640)
        popover.contentViewController = NSHostingController(
            rootView: MainPopoverView()
                .environmentObject(router)
                .environmentObject(registry)
                .environmentObject(settings)
                .environmentObject(updater)
                .environmentObject(remote)
        )

        // The popover window does not reliably follow NSApp.appearance, so apply the chosen theme to it directly.
        popover.appearance = settings.appearance.nsAppearance
        appearanceObserver = settings.$appearance.sink { [weak self] mode in
            self?.popover.appearance = mode.nsAppearance
        }

        if let button = statusItem.button {
            button.image = MenuBarController.makeIcon()
            button.image?.accessibilityDescription = "MacPeek"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "MacPeek"
        }

        // While Remote management is on, the icon carries a dot and the tooltip says so: it is never on unseen.
        remoteObserver = remote.$isEnabled.sink { [weak self] enabled in
            guard let button = self?.statusItem.button else { return }
            button.image = MenuBarController.makeIcon(remote: enabled)
            button.image?.accessibilityDescription = enabled ? "MacPeek, Remote management on" : "MacPeek"
            button.toolTip = enabled ? "MacPeek — Remote management is on" : "MacPeek"
        }
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
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Refresh", action: #selector(refreshNow), keyEquivalent: "r").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit MacPeek", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func refreshNow() { registry.refreshSummaries() }
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
