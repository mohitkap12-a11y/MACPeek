#if os(macOS)
import AppKit
import SwiftUI
import PortPeekCore

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let store: PortStore

    init(store: PortStore, settings: AppSettings) {
        self.store = store
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 380, height: 520)
        popover.contentViewController = NSHostingController(
            rootView: MainPopoverView()
                .environmentObject(store)
                .environmentObject(settings)
        )

        if let button = statusItem.button {
            button.image = MenuBarController.makeIcon()
            button.image?.accessibilityDescription = "PortPeek"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "PortPeek"
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
        menu.addItem(withTitle: "Quit PortPeek", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func refreshNow() { Task { await store.refresh() } }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: NSPopoverDelegate — poll only while the popover is visible.

    func popoverWillShow(_ notification: Notification) { store.startPolling() }
    func popoverDidClose(_ notification: Notification) { store.stopPolling() }

    /// Monochrome template icon: a magnifier whose lens holds a port "socket" dot.
    /// Template images adapt automatically to light/dark menu bars and Retina.
    static func makeIcon() -> NSImage {
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
            return true
        }
        image.isTemplate = true
        return image
    }
}
#endif
