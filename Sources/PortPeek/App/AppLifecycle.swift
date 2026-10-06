#if os(macOS)
import AppKit
import PortPeekCore

@MainActor
final class AppLifecycle: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = AppSettings()
        let discovery = LsofPortDiscovery()
        let store = PortStore(
            portService: PortService(discovery: discovery),
            killService: KillService(discovery: discovery),
            permissions: PermissionService(),
            settings: settings,
            notifier: NotificationService()
        )
        menuBar = MenuBarController(store: store, settings: settings)
        Log.app.info("PortPeek launched")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
#endif
