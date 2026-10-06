#if os(macOS)
import AppKit
import MacPeekCore
import PortPeekKit
import FileLockPeekKit
import DisplayPeekKit
import USBPeekKit
import SleepPeekKit
import ProcessPeekKit
import DiskPeekKit
import EnvPeekKit
import DNSPeekKit
import NetPeekKit

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

        let displayStore = DisplayStore(discovery: SystemProfilerDisplayDiscovery())
        let usbStore = USBStore(discovery: SystemUSBDiscovery())
        let sleepStore = SleepStore(reader: PMSetSleepReader(), settings: settings)

        let processStore = ProcessStore(
            lister: PSProcessLister(),
            terminator: ProcessTerminator(),
            permissions: PermissionService(),
            settings: settings,
            notifier: notifier
        )
        let diskStore = DiskStore(reader: SystemDiskIOReader(), settings: settings)
        let envStore = EnvStore(reader: SystemProcessEnvironmentReader())

        let dnsReader = SystemDNSReader()
        let dnsStore = DNSStore(reader: dnsReader)
        let netStore = NetStore(reader: SystemNetworkReader(dns: dnsReader), settings: settings)

        let registry = UtilityRegistry(modules: [
            PortPeekModule(store: portStore),
            DisplayPeekModule(store: displayStore),
            USBPeekModule(store: usbStore),
            SleepPeekModule(store: sleepStore),
            FileLockPeekModule(store: fileLockStore),
            ProcessPeekModule(store: processStore),
            DiskPeekModule(store: diskStore),
            EnvPeekModule(store: envStore),
            NetPeekModule(store: netStore),
            DNSPeekModule(store: dnsStore),
        ])
        let router = UtilityRouter(registry: registry)
        menuBar = MenuBarController(router: router, registry: registry, settings: settings)
        Log.app.info("MacPeek launched")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
#endif
