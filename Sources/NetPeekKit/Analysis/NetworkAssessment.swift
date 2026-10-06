import Foundation

/// A statement NetPeek makes, labelled by where it comes from.
public struct NetFinding: Equatable, Sendable {
    public enum Basis: Sendable {
        /// Read directly from macOS or a measurement.
        case verified
        /// A common explanation. Plausible, not proven.
        case inference
    }
    public let basis: Basis
    public let text: String

    public init(_ basis: Basis, _ text: String) {
        self.basis = basis
        self.text = text
    }
}

public enum NetworkAssessment {
    public static func headline(snapshot: NetSnapshot, checks: NetworkChecks?) -> String {
        guard let primary = snapshot.primary else { return "Not connected to a network" }
        if !snapshot.hasDefaultRoute { return "Connected to \(primary.displayName), but there is no route to the internet" }
        if primary.isReachable == false { return "macOS reports \(primary.displayName) as not reachable" }
        guard let checks else { return "Connected via \(primary.displayName)" }
        if case .result(let gateway)? = checks.gateway, !gateway.gotReplies { return "Your router did not answer" }
        let dnsReplies = checks.dnsServers.compactMap { outcome -> PingResult? in if case .result(let r) = outcome { return r }; return nil }
        if !dnsReplies.isEmpty, dnsReplies.allSatisfy({ !$0.gotReplies }) { return "Your DNS servers did not answer" }
        return "Connection looks healthy"
    }

    public static func findings(snapshot: NetSnapshot, wifi: WiFiInfo?, checks: NetworkChecks?) -> [NetFinding] {
        var result: [NetFinding] = []

        if let wifi, wifi.isConnected {
            if let signal = wifi.signalDBm {
                var text = "Wi-Fi signal \(signal) dBm"
                if let noise = wifi.noiseDBm, let snr = wifi.signalToNoise { text += ", noise \(noise) dBm (signal-to-noise \(snr) dB)" }
                result.append(NetFinding(.verified, text + "."))
                if let quality = wifi.signalQuality {
                    result.append(NetFinding(.inference, "That is \(quality.lowercased()) by the usual rule of thumb."))
                }
            }
        }

        guard let checks else { return result }
        if let gateway = checks.gateway { result.append(contentsOf: describe(gateway, label: "Router", isRouter: true, wifi: wifi)) }
        for server in checks.dnsServers { result.append(contentsOf: describe(server, label: "DNS server", isRouter: false, wifi: wifi)) }
        return result
    }

    private static func describe(_ outcome: PingOutcome, label: String, isRouter: Bool, wifi: WiFiInfo?) -> [NetFinding] {
        switch outcome {
        case .skipped(let host, let reason):
            return [NetFinding(.verified, "\(label) \(host) was not checked. \(reason)")]
        case .failed(let host, let reason):
            return [NetFinding(.verified, "\(label) \(host): the check could not run (\(reason))")]
        case .result(let r):
            var lines: [NetFinding] = []
            if r.gotReplies {
                let avg = r.averageMilliseconds.map { String(format: ", average %.0f ms", $0) } ?? ""
                lines.append(NetFinding(.verified, "\(label) \(r.host): \(r.received) of \(r.transmitted) replies\(avg)."))
                if r.lossPercent >= 20 {
                    lines.append(NetFinding(.inference, isRouter && wifi?.isConnected == true
                        ? "Lost packets to the router often mean a weak signal or Wi-Fi interference."
                        : "Lost packets can mean congestion or an unreliable link."))
                }
                if isRouter, let avg = r.averageMilliseconds, avg > 50 {
                    lines.append(NetFinding(.inference, "That is slow for a device one hop away: congestion or a weak signal are common causes."))
                }
            } else {
                lines.append(NetFinding(.verified, "\(label) \(r.host): no replies to \(r.transmitted) pings."))
                lines.append(NetFinding(.inference, "Some devices ignore pings, so no reply does not prove the connection is down."))
            }
            return lines
        }
    }
}
