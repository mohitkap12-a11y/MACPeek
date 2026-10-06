#if os(macOS)
import Foundation
import NetPeekKit

/// Observable state for NetPeek. The cheap connection snapshot refreshes while the screen is visible; Wi-Fi details
/// (a slower `system_profiler` call) load once per visit; pings run only when the user presses "Run checks".
/// Leaving the screen stops everything and forgets the measurements.
@MainActor
final class NetStore: ObservableObject {
    @Published private(set) var snapshot: NetSnapshot?
    @Published private(set) var error: String?
    @Published private(set) var wifi: WiFiInfo?
    @Published private(set) var isLoadingWiFi = false
    @Published private(set) var checks: NetworkChecks?
    @Published private(set) var isChecking = false
    @Published private(set) var checksError: String?

    private let reader: NetworkReading
    private let settings: AppSettings
    private var pollTask: Task<Void, Never>?
    private var wifiTask: Task<Void, Never>?
    private var checksTask: Task<Void, Never>?
    private var wifiInterface: String?
    /// Each read gets a number; only the newest read may publish, so a slow earlier read cannot overwrite a later one.
    private var readGeneration = 0

    init(reader: NetworkReading, settings: AppSettings) {
        self.reader = reader
        self.settings = settings
    }

    var headline: String? { snapshot.map { NetworkAssessment.headline(snapshot: $0, checks: checks) } }
    var findings: [NetFinding] { snapshot.map { NetworkAssessment.findings(snapshot: $0, wifi: wifi, checks: checks) } ?? [] }

    /// One read, for the launcher summary and manual refresh.
    func refresh() async {
        readGeneration += 1
        let generation = readGeneration
        do {
            let result = try await reader.snapshot()
            guard !Task.isCancelled, generation == readGeneration else { return }
            // Measurements describe the router and servers they ran against: drop them (and stop any run) when those change.
            if let old = snapshot, !Self.sameTargets(old, result) {
                checksTask?.cancel()
                checksTask = nil
                checks = nil
                isChecking = false
            }
            snapshot = result
            error = nil
            updateWiFi(for: result)
        } catch {
            if Task.isCancelled || generation != readGeneration { return }
            self.error = error.localizedDescription
            Log.netPeek.error("read failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func sameTargets(_ a: NetSnapshot, _ b: NetSnapshot) -> Bool {
        a.primary?.name == b.primary?.name && a.gateway == b.gateway && a.dnsServers == b.dnsServers
    }

    func reloadWiFi() {
        wifiInterface = nil
        if let snapshot { updateWiFi(for: snapshot) }
    }

    func startPolling() {
        stopPolling()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let seconds = max(self.settings.refreshInterval, 5)
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
        }
    }

    /// Stops all work and forgets measurements: a ping result describes the moment it ran.
    func stopPolling() {
        pollTask?.cancel()
        wifiTask?.cancel()
        checksTask?.cancel()
        pollTask = nil
        wifiTask = nil
        checksTask = nil
        isLoadingWiFi = false
        isChecking = false
        wifi = nil
        wifiInterface = nil
        checks = nil
        checksError = nil
    }

    private func updateWiFi(for snapshot: NetSnapshot) {
        guard let primary = snapshot.primary, primary.isWiFi else {
            wifiTask?.cancel()
            wifi = nil
            wifiInterface = nil
            isLoadingWiFi = false
            return
        }
        guard wifiInterface != primary.name else { return }
        wifiInterface = primary.name
        wifiTask?.cancel()
        isLoadingWiFi = true
        let name = primary.name
        wifiTask = Task { [weak self] in
            guard let self else { return }
            defer { if !Task.isCancelled { self.isLoadingWiFi = false } }
            do {
                let info = try await self.reader.wifi(interface: name)
                guard !Task.isCancelled else { return }
                self.wifi = info
            } catch {
                if Task.isCancelled { return }
                Log.netPeek.error("wifi read failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func runChecks() {
        guard let snapshot, snapshot.hasDefaultRoute else { return }
        checksTask?.cancel()
        checks = nil
        checksError = nil
        isChecking = true
        checksTask = Task { [weak self] in
            guard let self else { return }
            defer { if !Task.isCancelled { self.isChecking = false } }
            do {
                let result = try await self.reader.runChecks(for: snapshot)
                guard !Task.isCancelled, let current = self.snapshot, Self.sameTargets(current, snapshot) else { return }
                self.checks = result
            } catch {
                if Task.isCancelled { return }
                self.checksError = error.localizedDescription
                Log.netPeek.error("checks failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
#endif
