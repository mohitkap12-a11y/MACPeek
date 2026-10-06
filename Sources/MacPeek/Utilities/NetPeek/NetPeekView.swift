#if os(macOS)
import SwiftUI
import NetPeekKit

/// NetPeek's screen: how the Mac is connected, Wi-Fi details, and (on request) whether the router and DNS servers answer.
struct NetPeekView: View {
    @EnvironmentObject private var store: NetStore

    var body: some View {
        VStack(spacing: 0) {
            if let error = store.error, store.snapshot != nil {
                BannerView(banner: Banner(kind: .error, text: "Couldn't refresh: \(error) Showing the last reading."))
            }
            content
            Divider()
            footer
        }
    }

    @ViewBuilder private var content: some View {
        if let error = store.error, store.snapshot == nil {
            ErrorState(message: error, retryTitle: "Try again") { Task { await store.refresh() } }
        } else if let snapshot = store.snapshot {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ConnectionCard(snapshot: snapshot)
                    if snapshot.primary?.isWiFi == true { WiFiCard() }
                    ChecksCard(snapshot: snapshot)
                    OtherInterfaces(snapshot: snapshot)
                }
                .padding(12)
            }
            .frame(maxHeight: .infinity)
        } else {
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading network information…").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack {
            Text("Pings only when you press Run checks")
            Spacer()
            Button { store.reloadWiFi(); Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Refresh now")
                .keyboardShortcut("r", modifiers: .command)
                .accessibilityLabel("Refresh network information")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

private struct ConnectionCard: View {
    @EnvironmentObject private var store: NetStore
    let snapshot: NetSnapshot

    private var symbol: String {
        guard let primary = snapshot.primary else { return "wifi.slash" }
        return primary.isWiFi ? "wifi" : "network"
    }

    private var rows: [(label: String, value: String)] {
        guard let primary = snapshot.primary else { return [] }
        var rows: [(label: String, value: String)] = [("Interface", "\(primary.displayName) (\(primary.name))")]
        if !primary.ipv4Addresses.isEmpty { rows.append(("IPv4", primary.ipv4Addresses.joined(separator: ", "))) }
        if !primary.ipv6Addresses.isEmpty { rows.append(("IPv6", primary.ipv6Addresses.joined(separator: ", "))) }
        if let gateway = snapshot.gateway { rows.append(("Router", gateway)) }
        if !snapshot.dnsServers.isEmpty { rows.append(("DNS servers", snapshot.dnsServers.joined(separator: ", "))) }
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                IconTile(symbol: symbol)
                Text(store.headline ?? "").font(.system(size: 13, weight: .semibold)).lineLimit(2)
                Spacer(minLength: 4)
                CopyButton(text: snapshot.copyText, label: "Copy connection details")
            }
            if !rows.isEmpty { KeyValueRows(rows: rows) }
        }
        .peekCard()
    }
}

private struct WiFiCard: View {
    @EnvironmentObject private var store: NetStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Wi-Fi").font(.caption.weight(.semibold))
                if store.isLoadingWiFi { ProgressView().controlSize(.small) }
                Spacer()
            }
            if let wifi = store.wifi {
                if wifi.isConnected {
                    KeyValueRows(rows: rows(wifi))
                    if wifi.networkName == nil {
                        Text("macOS hides the network name from apps that do not have Location access. MacPeek does not ask for it.")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                } else {
                    Text("Wi-Fi is not connected to a network.").font(.caption).foregroundStyle(.secondary)
                }
            } else if !store.isLoadingWiFi {
                Text("Wi-Fi details are not available.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .peekCard()
    }

    private func rows(_ wifi: WiFiInfo) -> [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = [("Network", wifi.networkName ?? "Hidden by macOS")]
        if let dbm = wifi.signalDBm { rows.append(("Signal", "\(dbm) dBm" + (wifi.signalQuality.map { " · \($0) (rule of thumb)" } ?? ""))) }
        if let noise = wifi.noiseDBm, let snr = wifi.signalToNoise { rows.append(("Noise", "\(noise) dBm · signal-to-noise \(snr) dB")) }
        if let channel = wifi.channel { rows.append(("Channel", channel)) }
        if let phy = wifi.phyMode { rows.append(("Standard", phy)) }
        if let rate = wifi.transmitRateMbps { rows.append(("Link rate", "\(rate) Mb/s (radio, not internet speed)")) }
        if let security = wifi.security { rows.append(("Security", security)) }
        return rows
    }
}

private struct ChecksCard: View {
    @EnvironmentObject private var store: NetStore
    let snapshot: NetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Connection checks").font(.caption.weight(.semibold))
                Spacer()
                if store.isChecking { ProgressView().controlSize(.small) }
                Button("Run checks") { store.runChecks() }
                    .controlSize(.small)
                    .disabled(store.isChecking || !snapshot.hasDefaultRoute)
            }
            Text("Sends three pings to your router and to up to three of your DNS servers (IPv4 only). DNS servers are often outside your home network, such as a public resolver, so those pings do leave it.")
                .font(.caption2).foregroundStyle(.tertiary)
            if let error = store.checksError { Text(error).font(.caption).foregroundStyle(.orange) }
            ForEach(Array(store.findings.enumerated()), id: \.offset) { _, finding in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: finding.basis == .verified ? "checkmark.seal" : "lightbulb")
                        .font(.caption)
                        .foregroundStyle(finding.basis == .verified ? Color.green : Color.orange)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(finding.basis == .verified ? "Measured or reported" : "Likely (inference)")
                            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        Text(finding.text).font(.caption).textSelection(.enabled)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .peekCard()
    }
}

private struct OtherInterfaces: View {
    let snapshot: NetSnapshot

    var body: some View {
        if !snapshot.otherInterfaces.isEmpty {
            DisclosureGroup("Other connections (\(snapshot.otherInterfaces.count))") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(snapshot.otherInterfaces) { interface in
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(interface.displayName) (\(interface.name))").font(.caption.weight(.medium))
                            Text((interface.ipv4Addresses + interface.ipv6Addresses).joined(separator: ", "))
                                .font(.caption2.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
            .font(.caption)
        }
    }
}
#endif
