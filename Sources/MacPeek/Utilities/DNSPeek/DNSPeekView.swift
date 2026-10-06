#if os(macOS)
import SwiftUI
import DNSPeekKit

/// DNSPeek's screen: which DNS servers macOS uses, and (on request) whether they respond.
struct DNSPeekView: View {
    @EnvironmentObject private var store: DNSStore

    var body: some View {
        VStack(spacing: 0) {
            if let error = store.error, store.configuration != nil {
                BannerView(banner: Banner(kind: .error, text: "Couldn't refresh: \(error) Showing the last reading."))
            }
            content
            Divider()
            footer
        }
    }

    @ViewBuilder private var content: some View {
        if let error = store.error, store.configuration == nil {
            ErrorState(message: error, retryTitle: "Try again") { store.refresh() }
        } else if let configuration = store.configuration {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ServersCard(configuration: configuration)
                    LookupCard(servers: configuration.activeServers)
                    OtherResolvers(configuration: configuration)
                }
                .padding(12)
            }
            .frame(maxHeight: .infinity)
        } else {
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading DNS configuration…").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack {
            Text("Read-only · never changes DNS settings")
            Spacer()
            if store.isLoading { ProgressView().controlSize(.small) }
            Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Read again")
                .keyboardShortcut("r", modifiers: .command)
                .accessibilityLabel("Read DNS configuration again")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

private struct ServersCard: View {
    let configuration: DNSConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                IconTile(symbol: "server.rack")
                VStack(alignment: .leading, spacing: 1) {
                    Text("DNS servers in use").font(.system(size: 13, weight: .semibold))
                    if let interface = configuration.primary?.interface {
                        Text("on \(interface)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                if let reachable = configuration.primary?.isReachable {
                    StatusBadge(text: reachable ? "Reachable" : "Not reachable", tone: reachable ? .good : .warning)
                }
                CopyButton(text: configuration.copyText, label: "Copy DNS configuration")
            }
            if configuration.activeServers.isEmpty {
                Text("macOS reports no DNS servers. Names cannot be resolved.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(Array(configuration.activeServers.enumerated()), id: \.offset) { index, server in
                    HStack(spacing: 6) {
                        Text("\(index + 1)").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary).frame(width: 14)
                        Text(server).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                        CopyButton(text: server, label: "Copy \(server)")
                    }
                }
            }
            if !configuration.searchDomains.isEmpty {
                KeyValueRows(rows: [("Search domains", configuration.searchDomains.joined(separator: ", "))])
            }
        }
        .peekCard()
    }
}

private struct LookupCard: View {
    @EnvironmentObject private var store: DNSStore
    let servers: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Check that they respond").font(.caption.weight(.semibold))
            HStack(spacing: 6) {
                TextField("Domain to look up", text: $store.lookupName)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onSubmit { store.runLookup() }
                    .accessibilityLabel("Domain to look up")
                Button("Run lookup") { store.runLookup() }
                    .disabled(store.isLookingUp || servers.isEmpty)
            }
            .controlSize(.small)
            Text("Sends DNS queries for this name to your resolver and to each server above. Nothing else is sent.")
                .font(.caption2).foregroundStyle(.tertiary)

            if store.isLookingUp { ProgressView().controlSize(.small) }
            if let error = store.lookupError { Text(error).font(.caption).foregroundStyle(.orange) }
            if let lookup = store.lookup {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Through macOS (what apps use)").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    if lookup.addresses.isEmpty {
                        Text("No answer for \(lookup.name).").font(.caption)
                    } else {
                        ForEach(lookup.addresses, id: \.self) { Text($0).font(.system(size: 11, design: .monospaced)).textSelection(.enabled) }
                        Text("about \(lookup.elapsedMilliseconds) ms, includes starting the tool and may come from a cache")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            if !store.probes.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Each server, asked directly").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(store.probes) { probe in ProbeRow(probe: probe) }
                }
            }
        }
        .peekCard()
    }
}

private struct ProbeRow: View {
    let probe: ServerProbe

    var body: some View {
        HStack(spacing: 6) {
            Text(probe.server).font(.system(size: 11, design: .monospaced))
            Spacer(minLength: 4)
            switch probe.outcome {
            case .answered(let ms, let status, let answers):
                StatusBadge(text: status == "NOERROR" ? "\(answers) answer\(answers == 1 ? "" : "s")" : status, tone: status == "NOERROR" ? .good : .warning)
                if let ms { Text("\(ms) ms").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            case .timedOut:
                StatusBadge(text: "No response", tone: .warning)
            case .unavailable(let reason):
                Text(reason).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct OtherResolvers: View {
    let configuration: DNSConfiguration

    var body: some View {
        let domain = configuration.domainResolvers
        let multicast = configuration.multicastResolvers
        if !domain.isEmpty || !multicast.isEmpty || !configuration.scopedResolvers.isEmpty {
            DisclosureGroup("Other resolvers") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(domain) { resolver in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(resolver.domain ?? "").font(.caption.weight(.medium))
                            Text(resolver.nameservers.joined(separator: ", ")).font(.caption2.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                    if !multicast.isEmpty {
                        Text("\(multicast.count) multicast DNS (mDNS) zones, such as .local, are answered on your local network, not by a server.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if !configuration.scopedResolvers.isEmpty {
                        Text("\(configuration.scopedResolvers.count) scoped resolver\(configuration.scopedResolvers.count == 1 ? "" : "s") for queries bound to one interface.")
                            .font(.caption2).foregroundStyle(.secondary)
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
