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
import SoundPeekKit
import StartupPeekKit
import UpdatePeekKit

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
        let usbStore = USBStore(discovery: SystemUSBDiscovery(), settings: settings)
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

        let soundStore = SoundStore(service: SoundPeekService(provider: CoreAudioDeviceProvider()),
                                    observer: CoreAudioChangeObserver())
        let startupStore = StartupStore(service: StartupInventoryService(
            providers: [OwnLoginItemProvider(reader: ServiceManagementOwnLoginItem()), LaunchdPlistProvider()],
            signatures: SecurityCodeSignatureReader()))
        let updateLocator = StandardHomebrewLocator()
        let updateStore = UpdateStore(service: UpdateStatusService(
            os: SystemOperatingSystem(), locator: updateLocator,
            homebrew: BrewOutdatedChecker(locator: updateLocator)))

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
            SoundPeekModule(store: soundStore),
            StartupPeekModule(store: startupStore),
            UpdatePeekModule(store: updateStore),
            PrivacyPeekModule(),
        ])
        let router = UtilityRouter(registry: registry)
        menuBar = MenuBarController(router: router, registry: registry, settings: settings)
        Self.installEditMenu()
        Log.app.info("MacPeek launched")
    }

    /// A menu-bar app has no main menu, so ⌘V/⌘C/⌘A/⌘X/⌘Z never reach text fields. An Edit menu (never shown, since the
    /// app has no menu bar) restores the standard key equivalents.
    private static func installEditMenu() {
        let main = NSMenu()
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        NSApp.mainMenu = main
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
#endif
