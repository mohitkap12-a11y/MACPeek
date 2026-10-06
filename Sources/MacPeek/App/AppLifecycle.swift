#if os(macOS)
import AppKit
import MacPeekCore
import PortPeekKit

@MainActor
final class AppLifecycle: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = AppSettings()

        // Each utility builds its own services; the shell only sees `UtilityModule`s.
        let discovery = LsofPortDiscovery()
        let portStore = PortStore(
            portService: PortService(discovery: discovery),
            killService: KillService(discovery: discovery),
            permissions: PermissionService(),
            settings: settings,
            notifier: NotificationService()
        )

        let registry = UtilityRegistry(modules: [PortPeekModule(store: portStore)])
        let router = UtilityRouter(registry: registry)
        menuBar = MenuBarController(router: router, registry: registry, settings: settings)
        Log.app.info("MacPeek launched")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
#endif
