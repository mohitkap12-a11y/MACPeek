#if os(macOS)
import Foundation
import Combine
import MacPeekCore
import CPUPeekKit
import MemoryPeekKit
import NetPeekKit
import GPUPeekKit
import SensorsKit
import VitalsKit

/// The one part of MacPeek that runs in the background, and only while something needs it: alerts (on by default),
/// the 24-hour history (on by default) or the menu-bar readout (off by default). With all three off it does nothing at
/// all. Each tick costs a few cheap reads (CPU ticks, memory counters, interface counters, sensors); the per-process
/// scan for runaway processes and memory growth runs every 10 seconds, and the GPU, which needs `ioreg`, every 30
/// seconds unless the menu bar shows it.
@MainActor
final class VitalsMonitor: ObservableObject {
    @Published private(set) var latest: VitalsSample?
    @Published private(set) var sensors: SensorSnapshot?
    /// Newest first, at most `alertLimit`. Kept across launches.
    @Published private(set) var recentAlerts: [AlertEvent] = []
    @Published private(set) var history = VitalsHistory()
    @Published private(set) var isRunning = false
    /// When the person last looked at the alerts screen; newer alerts put a dot on the launcher's bell.
    @Published private(set) var alertsSeenAt: Date

    static let alertLimit = 50
    static let tickSeconds: TimeInterval = 5
    static let processScanSeconds: TimeInterval = 10
    static let gpuSeconds: TimeInterval = 30
    static let saveSeconds: TimeInterval = 5 * 60

    let sensorReader: SensorReading
    private let settings: AppSettings
    private let cpuReader: CPUReading
    private let memoryReader: MemoryReading
    private let countersReader: InterfaceCountersReading
    private let processReader: ProcessUsageReading
    private let gpuReader: GPUReading
    private let file: VitalsHistoryFile?
    private let defaults: UserDefaults
    let notifier = AlertNotifier()

    private var engine = AlertEngine()
    private var processSampler = ProcessCPUSampler()
    private var traffic = TrafficSampler()
    private var previousCores: [CoreTicks]?
    private var lastProcessScan: Date?
    private var lastGPU: (date: Date, value: Double?)?
    private var lastSave = Date()
    private var lastPrune = Date.distantPast
    private var task: Task<Void, Never>?
    private var observers: Set<AnyCancellable> = []

    init(settings: AppSettings, sensorReader: SensorReading, cpuReader: CPUReading = SystemCPUReader(),
         memoryReader: MemoryReading = SystemMemoryReader(), countersReader: InterfaceCountersReading = SystemInterfaceCountersReader(),
         processReader: ProcessUsageReading = SystemProcessUsageReader(), gpuReader: GPUReading = SystemGPUReader(),
         file: VitalsHistoryFile? = VitalsHistoryFile.standard(), defaults: UserDefaults = .standard) {
        self.settings = settings
        self.sensorReader = sensorReader
        self.cpuReader = cpuReader
        self.memoryReader = memoryReader
        self.countersReader = countersReader
        self.processReader = processReader
        self.gpuReader = gpuReader
        self.file = file
        self.defaults = defaults
        alertsSeenAt = defaults.object(forKey: "alerts.seenAt") as? Date ?? .distantPast
        recentAlerts = defaults.data(forKey: "alerts.recent")
            .flatMap { try? JSONDecoder().decode([AlertEvent].self, from: $0) } ?? []
    }

    /// Loads the saved history and starts or stops with the settings that need the monitor.
    func start() {
        if settings.historyEnabled, let file { history = file.load() }
        notifier.install()
        notifier.onIgnore = { [weak self] name in self?.settings.ignoreInAlerts(name) }
        // Any change to what needs the monitor (or to the refresh interval the readout uses) restarts its loop.
        settings.objectWillChange
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.reconfigure() }
            .store(in: &observers)
        reconfigure()
    }

    var historyEnabled: Bool { settings.historyEnabled }
    var alertsEnabled: Bool { settings.alertsEnabled }

    private var isNeeded: Bool { settings.alertsEnabled || settings.historyEnabled || !settings.menuBarMetrics.isEmpty }

    private var interval: TimeInterval {
        settings.menuBarMetrics.isEmpty ? Self.tickSeconds : min(settings.refreshInterval, Self.tickSeconds)
    }

    private var configuredInterval: TimeInterval?

    private func reconfigure() {
        if !settings.historyEnabled, !history.isEmpty {
            history.clear()
            file?.delete()
        }
        guard isNeeded else {
            stop()
            return
        }
        guard task == nil || configuredInterval != interval else { return }
        stop()
        configuredInterval = interval
        isRunning = true
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                try? await Task.sleep(nanoseconds: SamplingSchedule.nanoseconds(self.interval))
            }
        }
    }

    private func stop() {
        task?.cancel()
        task = nil
        configuredInterval = nil
        isRunning = false
        previousCores = nil
        traffic = TrafficSampler()
        processSampler = ProcessCPUSampler()
        lastProcessScan = nil
        latest = nil
        // Nothing was watched while stopped, so no condition may count time from before.
        engine = AlertEngine()
    }

    /// Saves the history now (when MacPeek quits).
    func save() {
        guard settings.historyEnabled, let file else { return }
        do { try file.save(history) } catch { Log.vitals.error("saving history failed: \(error.localizedDescription, privacy: .public)") }
        lastSave = Date()
    }

    var hasUnseenAlerts: Bool { (recentAlerts.first?.time ?? .distantPast) > alertsSeenAt }

    func markAlertsSeen() {
        alertsSeenAt = Date()
        defaults.set(alertsSeenAt, forKey: "alerts.seenAt")
    }

    func clearAlerts() {
        recentAlerts = []
        defaults.removeObject(forKey: "alerts.recent")
    }

    func clearHistory() {
        history.clear()
        file?.delete()
    }

    // MARK: - Sampling

    private struct Reading: Sendable {
        var snapshot: CPUSnapshot?
        var memory: MemoryStats?
        var counters: [InterfaceCounters]?
        var processes: ProcessUsageSnapshot?
        var sensors: SensorSnapshot?
        var gpu: Double??
    }

    private func tick() async {
        let now = Date()
        let alerts = settings.alertsEnabled
        let wantsProcesses = alerts && settings.alertSettings.needsProcesses
            && (lastProcessScan.map { now.timeIntervalSince($0) >= Self.processScanSeconds - 0.5 } ?? true)
        let menuGPU = settings.menuBarMetrics.contains(.gpu)
        let wantsGPU = (menuGPU || settings.historyEnabled)
            && (lastGPU.map { now.timeIntervalSince($0.date) >= (menuGPU ? 0 : Self.gpuSeconds) } ?? true)
        let wantsSensors = settings.historyEnabled || settings.menuBarMetrics.contains(.temperature)
        let cpuReader = cpuReader, memoryReader = memoryReader, countersReader = countersReader
        let processReader = processReader, sensorReader = sensorReader, gpuReader = gpuReader

        let reading = await Task.detached(priority: .utility) { () async -> Reading in
            var reading = Reading()
            reading.snapshot = try? cpuReader.snapshot()
            reading.memory = try? memoryReader.read()
            reading.counters = try? countersReader.read()
            if wantsProcesses { reading.processes = try? processReader.read() }
            if wantsSensors { reading.sensors = sensorReader.read() }
            if wantsGPU {
                let gpus = try? await gpuReader.gpus()
                reading.gpu = .some(gpus?.compactMap(\.deviceUtilization).max().map { $0 / 100 })
            }
            return reading
        }.value
        guard !Task.isCancelled else { return }

        var sample = VitalsSample(time: now)
        if let snapshot = reading.snapshot {
            if let previous = previousCores { sample.cpu = CoreUsage.between(previous, snapshot.cores)?.total }
            previousCores = snapshot.cores
            sample.thermal = snapshot.thermal
        }
        if let stats = reading.memory {
            let breakdown = MemoryBreakdown(stats)
            sample.memoryUsed = breakdown.physical > 0 ? Double(breakdown.used) / Double(breakdown.physical) : nil
            sample.pressure = stats.pressure
            sample.swapUsedBytes = stats.swapUsedBytes
        }
        if let counters = reading.counters, let throughput = traffic.ingest(counters, at: now) {
            sample.networkIn = throughput.inBytesPerSecond
            sample.networkOut = throughput.outBytesPerSecond
        }
        if let sensors = reading.sensors {
            self.sensors = sensors
            sample.temperature = sensors.headlineCelsius
            sample.power = sensors.systemWatts
        }
        if let gpu = reading.gpu {
            lastGPU = (now, gpu)
        }
        sample.gpu = lastGPU?.value

        var observed: [ProcessObservation]?
        if let processes = reading.processes {
            lastProcessScan = now
            let rows = processSampler.ingest(processes.usages, at: now)
            let percent = Dictionary(rows.map { ($0.pid, $0.percent) }, uniquingKeysWith: { first, _ in first })
            let ownPID = Int(ProcessInfo.processInfo.processIdentifier)
            observed = processes.usages.filter { $0.pid != ownPID }.map {
                ProcessObservation(pid: $0.pid, generation: $0.generation, name: $0.name,
                                   cpuPercent: processSampler.isBaselineOnly ? nil : percent[$0.pid] ?? 0,
                                   footprintBytes: $0.memoryFootprintBytes)
            }
        }

        latest = sample

        if settings.historyEnabled {
            history.record(sample)
            if now.timeIntervalSince(lastPrune) >= 60 {
                history.prune(now: now)
                lastPrune = now
            }
            if now.timeIntervalSince(lastSave) >= Self.saveSeconds { save() }
        }

        if alerts {
            let observation = AlertObservation(time: now, processes: observed, pressure: sample.pressure,
                                               swapUsedBytes: sample.swapUsedBytes,
                                               networkBytesPerSecond: sample.networkIn.map { $0 + (sample.networkOut ?? 0) },
                                               thermal: sample.thermal)
            let events = engine.evaluate(observation, settings: settings.alertSettings)
            if !events.isEmpty { raise(events) }
        } else {
            // Alerts off while history or the readout keeps the monitor running: forget every episode, so turning
            // alerts back on starts each condition's clock afresh instead of alerting from an old start time.
            engine = AlertEngine()
        }
    }

    private func raise(_ events: [AlertEvent]) {
        recentAlerts = Array((events.reversed() + recentAlerts).prefix(Self.alertLimit))
        defaults.set(try? JSONEncoder().encode(recentAlerts), forKey: "alerts.recent")
        for event in events {
            Log.vitals.info("alert: \(event.title, privacy: .public)")
            notifier.post(event)
        }
    }
}
#endif
