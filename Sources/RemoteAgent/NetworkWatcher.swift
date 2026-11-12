#if canImport(Network)
import Foundation
import Network

/// Tells when this Mac's network really changes (Wi-Fi off and on, another network, Ethernet plugged in, the network
/// coming back), so the relay connection is made again at once on the new network instead of after its back-off, and a
/// socket left on the old network is not waited on. macOS also repeats the same network every half minute or so on some
/// Macs: those reports are not changes. A burst of reports is handled once, a second after the last.
public final class NetworkWatcher: @unchecked Sendable {
    private let queue = DispatchQueue(label: "MacPeek.RemoteAgent.Network")
    private let onChange: @Sendable (_ summary: String) -> Void
    private var monitor: NWPathMonitor?
    private var lastSignature: String?
    private var pending: DispatchWorkItem?

    /// `onChange` is called on a background queue once the network is up again or different, with a short description.
    public init(onChange: @escaping @Sendable (_ summary: String) -> Void) {
        self.onChange = onChange
    }

    public func start() {
        queue.async { [self] in
            guard monitor == nil else { return }
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { [weak self] path in self?.update(path) }
            self.monitor = monitor
            monitor.start(queue: queue)
        }
    }

    public func stop() {
        queue.async { [self] in
            monitor?.cancel()
            monitor = nil
            lastSignature = nil
            pending?.cancel()
            pending = nil
        }
    }

    private func update(_ path: NWPath) {
        let signature = Self.signature(of: path)
        defer { lastSignature = signature }
        // The first report describes the network when watching started, not a change.
        guard let last = lastSignature, last != signature, path.status == .satisfied else { return }
        pending?.cancel()
        let summary = Self.summary(of: path)
        let work = DispatchWorkItem { [onChange] in onChange(summary) }
        pending = work
        queue.asyncAfter(deadline: .now() + 1, execute: work)
    }

    /// Status, interfaces in macOS's order of preference (the first is in use), routers, IPv4/IPv6 and cost: the same
    /// network reported again gives the same signature.
    static func signature(of path: NWPath) -> String {
        var seen = Set<String>()
        let interfaces = path.availableInterfaces.map { "\($0.name)/\($0.type)" }.filter { seen.insert($0).inserted }
        let gateways = Set(path.gateways.map { "\($0)" }).sorted()
        return [
            "\(path.status)",
            interfaces.joined(separator: ","),
            gateways.joined(separator: ","),
            "v4:\(path.supportsIPv4) v6:\(path.supportsIPv6)",
            "expensive:\(path.isExpensive) constrained:\(path.isConstrained)",
        ].joined(separator: "|")
    }

    static func summary(of path: NWPath) -> String {
        guard let first = path.availableInterfaces.first else { return "\(path.status)" }
        return "\(path.status) via \(first.name)"
    }
}
#endif
