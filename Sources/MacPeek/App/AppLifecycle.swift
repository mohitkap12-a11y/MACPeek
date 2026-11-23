#if os(macOS)
import AppKit
import Combine
import MacPeekCore
import PortPeekKit
import FileLockPeekKit
import DisplayPeekKit
import USBPeekKit
import SleepPeekKit
import ProcessPeekKit
import DiskPeekKit
import MemoryPeekKit
import CPUPeekKit
import EnvPeekKit
import DNSPeekKit
import NetPeekKit
import SoundPeekKit
import UpdatePeekKit
import ContainerPeekKit
import GPUPeekKit
import ModelPeekKit
import SensorsKit
import VitalsKit

@MainActor
final class AppLifecycle: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var remote: RemoteManagementController?
    private var remoteIntro: RemoteIntroController?
    private var monitor: VitalsMonitor?
    private var welcome: WelcomeController?
    private var observers: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = AppSettings()
        let updater = UpdaterService()
        // One sensor reader (it holds the SMC connection and the HID client) for the monitor, CPUPeek, GPUPeek and the
        // Remote agent.
        let sensors = SystemSensorReader()
        // Alerts, the 24-hour history and the menu-bar readout. It runs only while one of them is on.
        let monitor = VitalsMonitor(settings: settings, sensorReader: sensors)
        self.monitor = monitor
        let remote = RemoteManagementController(vitals: monitor)
        self.remote = remote

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
        let usbStore = USBStore(discovery: SystemUSBDiscovery(), bluetooth: SystemBluetoothReader(), settings: settings)
        let sleepStore = SleepStore(reader: PMSetSleepReader(), settings: settings)

        let processStore = ProcessStore(
            lister: PSProcessLister(),
            insight: SystemProcessInsightReader(),
            terminator: ProcessTerminator(),
            permissions: PermissionService(),
            settings: settings,
            notifier: notifier
        )
        // One libproc reader (and its name cache) shared by DiskPeek, MemoryPeek and CPUPeek. Only one utility screen
        // is open at a time, so their scans never overlap.
        let processUsageReader = SystemProcessUsageReader()
        let diskStore = DiskStore(reader: SystemDiskIOReader(usage: processUsageReader),
                                  volumeReader: SystemVolumeCapacityReader(), settings: settings)
        let memoryStore = MemoryStore(reader: SystemMemoryReader(), processReader: processUsageReader, settings: settings)
        let cpuStore = CPUStore(reader: SystemCPUReader(), processReader: processUsageReader, sensors: sensors, settings: settings)
        let envStore = EnvStore(reader: SystemProcessEnvironmentReader())

        let dnsReader = SystemDNSReader()
        let dnsStore = DNSStore(reader: dnsReader, overridesReader: FileDNSOverridesReader())
        let netReader = SystemNetworkReader(dns: dnsReader)
        let netStore = NetStore(reader: netReader, extrasReader: netReader, settings: settings)

        let soundStore = SoundStore(service: SoundPeekService(provider: CoreAudioDeviceProvider()),
                                    observer: CoreAudioChangeObserver())
        let updateLocator = StandardHomebrewLocator()
        let npmLocator = StandardNpmLocator()
        let updateStore = UpdateStore(service: UpdateStatusService(
            os: SystemOperatingSystem(), locator: updateLocator,
            homebrew: BrewOutdatedChecker(locator: updateLocator),
            npmLocator: npmLocator, npm: NpmOutdatedChecker(locator: npmLocator),
            npmInstaller: NpmGlobalInstaller(locator: npmLocator),
            macOSRecord: PreferencesSoftwareUpdateRecord(), macOSChecker: SoftwareUpdateChecker()))

        // GPUPeek's power sampler subscribes to macOS's energy counters once; it is only sampled while GPUPeek is open.
        let gpuReader = SystemGPUReader(power: IOReportPowerSampler(), deviceFacts: MetalDeviceFactsReader())
        let gpuStore = GPUStore(reader: gpuReader, sensors: sensors, settings: settings)
        let containerStore = ContainerStore(reader: SystemContainerReader(usage: processUsageReader),
                                            controller: SystemContainerController(), settings: settings)
        // ModelPeek reads GPU clients without the power sampler: it only needs per-process GPU time.
        let modelStore = ModelStore(reader: SystemModelReader(usage: processUsageReader, gpu: SystemGPUReader()), settings: settings)

        let registry = UtilityRegistry(modules: [
            PortPeekModule(store: portStore),
            DisplayPeekModule(store: displayStore),
            USBPeekModule(store: usbStore),
            SleepPeekModule(store: sleepStore),
            MemoryPeekModule(store: memoryStore),
            CPUPeekModule(store: cpuStore),
            FileLockPeekModule(store: fileLockStore),
            ProcessPeekModule(store: processStore),
            DiskPeekModule(store: diskStore),
            EnvPeekModule(store: envStore),
            NetPeekModule(store: netStore),
            DNSPeekModule(store: dnsStore),
            SoundPeekModule(store: soundStore),
            UpdatePeekModule(store: updateStore),
            GPUPeekModule(store: gpuStore),
            ContainerPeekModule(store: containerStore),
            ModelPeekModule(store: modelStore),
        ])
        registry.gaugeRefreshInterval = { [weak settings] in settings?.refreshInterval ?? 2 }
        // While the menu bar shows CPU, memory or GPU, their launcher rings show the menu bar's own reading, so the two
        // never disagree (two readings over different moments differ by a point or two).
        let sharedMetrics: [String: MenuBarMetric] = ["cpupeek": .cpu, "memorypeek": .memory, "gpupeek": .gpu]
        let ringTints: [String: LauncherGauge.Tint] = ["cpupeek": .accent, "memorypeek": .amber, "gpupeek": .accent]
        registry.sharedGauge = { [weak monitor] id in
            guard let metric = sharedMetrics[id], let reading = monitor?.gaugeReading(for: metric) else { return nil }
            return LauncherGauge(reading, tint: ringTints[id] ?? .accent)
        }
        // `$live` fires before the value is stored; the task runs after, so it reads the new reading.
        monitor.$live
            .sink { [weak monitor, weak registry, weak cpuStore] _ in
                Task { @MainActor in
                    if let live = monitor?.live, let cpu = live.cpu { cpuStore?.adoptBaseline(cpu.snapshot, at: live.time) }
                    registry?.applySharedGauges()
                }
            }
            .store(in: &observers)
        let router = UtilityRouter(registry: registry)
        // The introduction to MacPeek Remote: the launcher's row opens it, and it opens by itself when due.
        let remoteIntro = RemoteIntroController(settings: settings)
        self.remoteIntro = remoteIntro
        let menuBar = MenuBarController(router: router, registry: registry, settings: settings, updater: updater,
                                        remote: remote, remoteIntro: remoteIntro, monitor: monitor)
        self.menuBar = menuBar
        monitor.notifier.onShow = { [weak menuBar] in menuBar?.show(.alerts) }
        monitor.start()
        remoteIntro.start()
        // The first launch opens MacPeek, and says so when macOS hides the icon (a full menu bar, or the notch).
        let welcome = WelcomeController(menuBar: menuBar)
        self.welcome = welcome
        welcome.start()
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

    /// Launching MacPeek again while it runs opens it: under its icon, or in a window when the icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        menuBar?.reopen()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.save()
    }
}
#endif
