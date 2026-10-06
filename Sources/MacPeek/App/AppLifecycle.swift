#if os(macOS)
import AppKit
import MacPeekCore
import PortPeekKit
import FileLockPeekKit

@MainActor
final class AppLifecycle: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = AppSettings()

        // Each utility builds its own services; the shell only sees `UtilityModule`s.
        let discovery = LsofPortDiscovery()
        let notifier = NotificationService()
        let portStore = PortStore(
            portService: PortService(discovery: discovery),
            killService: KillService(discovery: discovery),
            permissions: PermissionService(),
            settings: settings,
            notifier: notifier
        )

        let fileDiscovery = LsofFileLockDiscovery()
        let fileLockStore = FileLockStore(
            service: FileLockService(discovery: fileDiscovery),
            terminator: FileLockTerminator(discovery: fileDiscovery),
            permissions: PermissionService(),
            settings: settings,
            notifier: notifier
        )

        let registry = UtilityRegistry(modules: [
            PortPeekModule(store: portStore),
            FileLockPeekModule(store: fileLockStore),
        ])
        let router = UtilityRouter(registry: registry)
        menuBar = MenuBarController(router: router, registry: registry, settings: settings)
        Log.app.info("MacPeek launched")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
#endif
