#if os(macOS)
import Foundation
import DNSPeekKit

/// Observable state for DNSPeek. The configuration is read when the screen opens or on request; lookups only run
/// when the user presses "Run lookup". Nothing happens in the background, and everything is cancelled on leave.
@MainActor
final class DNSStore: ObservableObject {
    @Published private(set) var configuration: DNSConfiguration?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    @Published var lookupName = "apple.com"
    @Published private(set) var isLookingUp = false
    @Published private(set) var lookup: SystemLookup?
    @Published private(set) var probes: [ServerProbe] = []
    @Published private(set) var lookupError: String?
    /// `/etc/hosts` and `/etc/resolver/*`, read with the configuration.
    @Published private(set) var overrides: DNSOverrides?

    private let reader: DNSReading
    private let overridesReader: DNSOverridesReading?
    private var loadTask: Task<Void, Never>?
    private var lookupTask: Task<Void, Never>?
    /// Bumped whenever the configuration changes, so a lookup against the old server list cannot show up under the new one.
    private var configGeneration = 0

    init(reader: DNSReading, overridesReader: DNSOverridesReading? = nil) {
        self.reader = reader
        self.overridesReader = overridesReader
    }

    /// Overrides that apply to the name in the lookup field.
    var lookupExplanation: [String] { overrides?.explain(name: lookupName) ?? [] }

    func refresh() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in await self?.load() }
    }

    /// One-off read for the launcher summary.
    func summary() async -> String? {
        await load()
        guard error == nil, let configuration else { return nil }
        let n = configuration.activeServers.count
        return n == 0 ? "No DNS servers" : (n == 1 ? "1 server" : "\(n) servers")
    }

    func cancel() {
        loadTask?.cancel()
        lookupTask?.cancel()
        loadTask = nil
        lookupTask = nil
        isLoading = false
        isLookingUp = false
        // The results of a check are about the moment it ran: do not keep them around.
        lookup = nil
        probes = []
        lookupError = nil
    }

    private func load() async {
        isLoading = true
        defer { if !Task.isCancelled { isLoading = false } }
        do {
            let result = try await reader.configuration()
            guard !Task.isCancelled else { return }
            if let overridesReader {
                // Two small local files: read off the main thread, but no need for a task of their own.
                overrides = await Task.detached(priority: .utility) { overridesReader.overrides() }.value
            }
            if let old = configuration, old.activeServers != result.activeServers {
                configGeneration += 1
                lookupTask?.cancel()
                lookupTask = nil
                isLookingUp = false
                lookup = nil
                probes = []
            }
            configuration = result
            error = nil
        } catch {
            if Task.isCancelled { return }
            self.error = error.localizedDescription
            Log.dnsPeek.error("read failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Looks the name up through the system resolver, then asks each active DNS server directly.
    func runLookup() {
        let name = lookupName.trimmingCharacters(in: .whitespaces)
        guard let servers = configuration?.activeServers else { return }
        lookupTask?.cancel()
        lookup = nil
        probes = []
        lookupError = nil
        isLookingUp = true
        let generation = configGeneration
        lookupTask = Task { [weak self] in
            guard let self else { return }
            defer { if !Task.isCancelled { self.isLookingUp = false } }
            do {
                let system = try await self.reader.lookup(name: name)
                guard !Task.isCancelled else { return }
                self.lookup = system
                var results: [ServerProbe] = []
                for server in servers.prefix(4) {
                    let probe: ServerProbe
                    do {
                        probe = try await self.reader.probe(server: server, name: name)
                    } catch DNSError.invalidServer {
                        // e.g. a link-local resolver printed with a zone id: report it, keep checking the others.
                        probe = ServerProbe(server: server, outcome: .unavailable("MacPeek can only query plain IP addresses directly."))
                    }
                    guard !Task.isCancelled, generation == self.configGeneration else { return }
                    results.append(probe)
                    self.probes = results
                }
            } catch {
                if Task.isCancelled { return }
                self.lookupError = error.localizedDescription
                Log.dnsPeek.error("lookup failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
#endif
