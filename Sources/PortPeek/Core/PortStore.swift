#if os(macOS)
import Foundation
import PortPeekCore

struct Banner: Equatable {
    enum Kind { case success, error }
    let kind: Kind
    let text: String
}

/// Observable state for the UI. Owns scanning/polling and the kill flow; contains no AppKit.
@MainActor
final class PortStore: ObservableObject {
    @Published private(set) var ports: [PortInfo] = []
    @Published var query = ""
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isScanning = false
    @Published private(set) var scanError: String?
    @Published var selectedID: PortInfo.ID?
    @Published private(set) var killingID: PortInfo.ID?
    /// Set when SIGTERM did not stop the process: the UI then offers an explicit force-kill.
    @Published private(set) var forceCandidate: PortInfo?
    @Published private(set) var banner: Banner?

    private let portService: PortService
    private let killService: KillService
    private let permissions: PermissionService
    private let settings: AppSettings
    private let notifier: NotificationService
    private var pollTask: Task<Void, Never>?
    private var bannerTask: Task<Void, Never>?

    init(portService: PortService, killService: KillService, permissions: PermissionService,
         settings: AppSettings, notifier: NotificationService) {
        self.portService = portService
        self.killService = killService
        self.permissions = permissions
        self.settings = settings
        self.notifier = notifier
    }

    var filteredPorts: [PortInfo] { PortSearch.filter(ports, query: query) }

    func capability(for port: PortInfo) -> TerminationCapability { permissions.capability(for: port) }

    // MARK: Scanning

    func refresh() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        do {
            ports = try await portService.scan()
            lastUpdated = Date()
            scanError = nil
            if let id = selectedID, !ports.contains(where: { $0.id == id }) { selectedID = nil }
        } catch {
            scanError = error.localizedDescription
            Log.scan.error("scan failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Scans immediately, then every `refreshInterval` seconds until `stopPolling()`.
    func startPolling() {
        stopPolling()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let nanos = UInt64(self.settings.refreshInterval * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: Termination

    func terminate(_ port: PortInfo) async { await run(port, force: false) }
    func forceTerminate(_ port: PortInfo) async { await run(port, force: true) }
    func dismissForce() { forceCandidate = nil }

    private func run(_ port: PortInfo, force: Bool) async {
        killingID = port.id
        forceCandidate = nil
        let result = force ? await killService.forceTerminate(port) : await killService.terminate(port)
        killingID = nil
        Log.kill.info("port \(port.port) pid \(port.pid): \(String(describing: result), privacy: .public)")

        switch result {
        case .stillRunning:
            forceCandidate = port
            show(Banner(kind: .error, text: result.message(for: port)))
        case .terminated:
            show(Banner(kind: .success, text: "✓ Port \(port.port) freed"))
            if settings.showNotifications { notifier.notifyFreed(port.port, processName: port.processName, pid: port.pid) }
        default:
            show(Banner(kind: result.isSuccess ? .success : .error, text: result.message(for: port)))
        }
        await refresh()
    }

    private func show(_ banner: Banner) {
        self.banner = banner
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if !Task.isCancelled { self?.banner = nil }
        }
    }
}
#endif
